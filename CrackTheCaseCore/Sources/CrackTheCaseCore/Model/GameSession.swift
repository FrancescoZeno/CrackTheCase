import Foundation

/// Host-side source of truth for the current game state.
///
/// `HostConnectivityService` owns and mutates this object as players join,
/// update their profile, or toggle ready; it then broadcasts a snapshot to
/// every connected client via `GameMessage.lobbyState`. Clients do not own a
/// `GameSession` of their own — they simply mirror the last broadcast state
/// (see `ClientConnectivityService`).
@MainActor
@Observable
public final class GameSession {
    public var players: [Player]
    public var phase: GamePhase

    /// 4-digit code shown on the Apple TV; clients must submit it via
    /// `.requestToJoin` before they're allowed to join with a nickname. A
    /// lightweight gate against strangers on the same Wi-Fi wandering in —
    /// not real security.
    public let joinCode: String

    /// Arrival order of players who finished the turn-order minigame,
    /// oldest finish first. Reset each time `beginMinigame()` runs.
    public var minigameFinishOrder: [UUID] = []
    /// Which of the 13 turn-order minigames is being played this round,
    /// re-rolled at random every time `beginMinigame()` runs.
    public var turnMinigame: TurnMinigame = TurnMinigame.allCases.randomElement()!
    /// Turn-order minigames already played, so `beginMinigame()` cycles
    /// through all 13 once each before any repeat. Deliberately **not**
    /// cleared by `resetToLobby()` — variety keeps accumulating across
    /// "Play Again" games too, only resetting once every minigame has come
    /// up at least once since the last reset.
    private var usedTurnMinigames: Set<TurnMinigame> = []
    /// The player penalized for finishing the minigame last, set only once
    /// everyone has finished. Consumed during room exploration.
    public var penalizedPlayerID: UUID?

    /// Turn order for room exploration, copied from `minigameFinishOrder`
    /// when `beginRoomSelection()` runs.
    public var turnOrder: [UUID] = []
    /// Index into `turnOrder` of the player whose turn it currently is.
    public var currentTurnIndex: Int = 0
    /// Public record of every room visited this round — never carries clue
    /// content, so it's safe to broadcast and show on the tvOS board.
    public var roomVisitLog: [RoomVisit] = []

    /// Which room currently holds each of the 3 clues. Starts at the fixed
    /// placement below; the Black-out event moves 2 of the 3 entries to new
    /// rooms mid-game via `reshuffleClueRoomsForBlackout()`.
    public var roundClueAssignments: [RoomID: Clue] = GameSession.defaultClueAssignments

    /// The fixed starting room for each of the 3 clues, before any
    /// Black-out reshuffling — also what `resetToLobby()` restores for a
    /// fresh "Play Again" game.
    private static let defaultClueAssignments: [RoomID: Clue] = [
        .cafeteria: Clue(
            title: "A strange recipe",
            text: "Tucked in the pages of the cafeteria recipe book is a note with a recipe no one has ever seen… and a suspicious stain."
        ),
        .dormitory: Clue(
            title: "A note on the pillow",
            text: "A folded note on a pillow: \"See you at midnight, like always. — E.\""
        ),
        .headmasterOffice: Clue(
            title: "A cancelled appointment",
            text: "On the headmaster's calendar, a line has been angrily crossed out: last night's 9 PM appointment."
        ),
    ]

    /// The actual culprit, chosen at random once per game session (and
    /// re-rolled by `resetToLobby()` for a fresh "Play Again" game). Never
    /// broadcast directly — only revealed implicitly by a correct
    /// `castAccusation` ending the game in `.victory`.
    public var culpritID: String

    /// The player currently casting their vote, if any.
    public var votingPlayerID: UUID?
    /// The most recently resolved vote. Safe to broadcast: only ever set
    /// after the accusation has already been committed.
    public var lastAccusation: Accusation?

    /// 1-indexed count of the current Minigame → Rooms → Notebook cycle.
    public var roundNumber = 1
    /// The round on which the Black-out event triggers. Always round 3 —
    /// every game gets exactly one Black-out, on the same round, so the
    /// pacing is consistent from playthrough to playthrough.
    public let blackoutRoundNumber = 3
    /// When the current Black-out task began, for the on-screen (scenic
    /// only) stopwatch. `nil` outside `.blackoutTask`.
    public var blackoutTaskStartedAt: Date?
    /// Players who have finished the Black-out emergency task this round.
    public var blackoutTaskFinishedPlayerIDs: [UUID] = []
    /// Which emergency task plays during the Black-out round, chosen once at
    /// session creation (and re-rolled by `resetToLobby()` for a fresh
    /// "Play Again" game).
    public var blackoutMinigame: BlackoutMinigame = BlackoutMinigame.allCases.randomElement()!
    /// The team's target output for the `lightRegulator` task, re-rolled each
    /// time `beginBlackoutTask()` runs. Unused by the other minigames.
    public var blackoutLightTarget: Double = 0
    /// The current average of every player's regulator slider, for the
    /// `lightRegulator` task. Unused by the other minigames.
    public var blackoutLightAverage: Double = 0
    /// Each player's current regulator slider value, for the `lightRegulator`
    /// task. Every connected player starts at 0 as soon as the task begins,
    /// so the average reflects everyone even before they've touched their
    /// slider.
    private var blackoutLightValues: [UUID: Double] = [:]
    /// How close `blackoutLightAverage` must land to `blackoutLightTarget`
    /// for the `lightRegulator` task to succeed. Public so the client-side
    /// UI (e.g. `BlackoutLightRegulatorView`'s "on target" indicator) can
    /// match the same threshold instead of guessing its own.
    public static let blackoutLightTolerance: Double = 2.0

    /// True while the current round is the one designated for the Black-out
    /// event.
    public var isCurrentRoundBlackout: Bool { roundNumber == blackoutRoundNumber }

    /// Minimum number of players required before the host can start the game.
    public static let minimumPlayerCount = 2

    public init(players: [Player] = [], phase: GamePhase = .lobby) {
        self.players = players
        self.phase = phase
        self.joinCode = String(format: "%04d", Int.random(in: 0..<10_000))
        self.culpritID = Suspects.all.randomElement()!.id
    }

    /// True once every connected player has pressed "Ready".
    public var allReady: Bool {
        !players.isEmpty && players.allSatisfy(\.isReady)
    }

    /// True once the lobby has enough ready players for the host to advance
    /// out of `.lobby` into `.starting`.
    public var canStart: Bool {
        phase == .lobby && allReady && players.count >= Self.minimumPlayerCount
    }

    public func upsert(_ player: Player) {
        if let index = players.firstIndex(where: { $0.id == player.id }) {
            players[index] = player
        } else {
            players.append(player)
        }
    }

    /// Removes a player and cascades the removal through every piece of
    /// derived state that references them, so nothing is left pointing at a
    /// player who's no longer in `players`:
    /// - `minigameFinishOrder`, so `allPlayersFinishedMinigame` can still
    ///   become true once the remaining players finish.
    /// - `turnOrder`/`currentTurnIndex`, so a departed player's turn doesn't
    ///   stall room exploration forever waiting for a choice that will never
    ///   come — the next player's turn simply takes its place.
    /// - `penalizedPlayerID`, if it was pointing at them.
    public func removePlayer(id: UUID) {
        players.removeAll { $0.id == id }
        minigameFinishOrder.removeAll { $0 == id }

        if let removedIndex = turnOrder.firstIndex(of: id) {
            turnOrder.remove(at: removedIndex)
            if removedIndex < currentTurnIndex {
                currentTurnIndex -= 1
            }
        }

        if penalizedPlayerID == id {
            penalizedPlayerID = nil
        }

        if votingPlayerID == id {
            // Don't leave everyone else locked out waiting for a vote that
            // will never come.
            votingPlayerID = nil
            phase = .notebook
        }

        blackoutTaskFinishedPlayerIDs.removeAll { $0 == id }

        if blackoutLightValues.removeValue(forKey: id) != nil {
            recalculateBlackoutLightAverage()
        }

        // The game needs at least `minimumPlayerCount` to make sense at
        // all — mid-game (not pre-game: `.lobby` already gates starting on
        // this same minimum), dropping below it interrupts the game rather
        // than silently continuing with a solo "detective". This doesn't
        // reset anything by itself — the host acknowledges it explicitly
        // (see `resetToLobby()`) once ready to return to the lobby.
        if phase != .lobby && players.count < Self.minimumPlayerCount {
            phase = .notEnoughPlayers
        }
    }

    /// Returns everyone to `.lobby` for a fresh game with the same
    /// connected players and the same join code — used both when the host
    /// acknowledges a `.notEnoughPlayers` interruption and when a finished
    /// game is replayed via "Play Again". Re-rolls the culprit and the
    /// Black-out minigame so the new game isn't a rerun of the last one,
    /// but deliberately leaves `usedTurnMinigames` untouched (variety keeps
    /// accumulating across games) and requires everyone to press "Ready"
    /// again.
    public func resetToLobby() {
        phase = .lobby
        for index in players.indices {
            players[index].isReady = false
        }

        roundNumber = 1
        minigameFinishOrder = []
        penalizedPlayerID = nil
        turnOrder = []
        currentTurnIndex = 0
        roomVisitLog = []
        roundClueAssignments = Self.defaultClueAssignments

        votingPlayerID = nil
        lastAccusation = nil

        blackoutTaskStartedAt = nil
        blackoutTaskFinishedPlayerIDs = []
        blackoutLightValues = [:]
        blackoutLightTarget = 0
        blackoutLightAverage = 0
        blackoutMinigame = BlackoutMinigame.allCases.randomElement()!

        culpritID = Suspects.all.randomElement()!.id
    }

    /// Picks an avatar for a newly-joining player: one not already used by a
    /// connected player, if one is free; otherwise falls back to any random
    /// avatar (more players than avatars means some duplication is
    /// unavoidable).
    public func nextAvatar() -> Avatar {
        let used = Set(players.map(\.avatar))
        let available = Avatar.allCases.filter { !used.contains($0) }
        return available.randomElement() ?? Avatar.allCases.randomElement() ?? .fox
    }

    /// True once every connected player has finished the turn-order minigame.
    public var allPlayersFinishedMinigame: Bool {
        phase == .minigame && !players.isEmpty && minigameFinishOrder.count == players.count
    }

    /// Transitions into `.minigame`, clears any previous round's progress,
    /// and rolls a fresh `turnMinigame` for this round — drawn from
    /// whichever of the 13 haven't appeared yet, so none repeats until
    /// every one of them has had a turn. Once the pool is exhausted, it
    /// reshuffles (all 13 become available again) before drawing.
    public func beginMinigame() {
        phase = .minigame
        minigameFinishOrder = []
        penalizedPlayerID = nil

        var remaining = Set(TurnMinigame.allCases).subtracting(usedTurnMinigames)
        if remaining.isEmpty {
            usedTurnMinigames = []
            remaining = Set(TurnMinigame.allCases)
        }
        let picked = remaining.randomElement()!
        usedTurnMinigames.insert(picked)
        turnMinigame = picked
    }

    /// Records a player's arrival, ignoring duplicates or unknown IDs.
    /// Sets `penalizedPlayerID` to the last arrival once everyone has finished.
    public func recordMinigameFinish(id: UUID) {
        guard phase == .minigame,
              players.contains(where: { $0.id == id }),
              !minigameFinishOrder.contains(id)
        else { return }

        minigameFinishOrder.append(id)
        if minigameFinishOrder.count == players.count {
            penalizedPlayerID = minigameFinishOrder.last
        }
    }

    // MARK: - Room exploration (Phase 3)

    /// The player whose turn it currently is, if any turns remain.
    public var currentTurnPlayerID: UUID? {
        guard turnOrder.indices.contains(currentTurnIndex) else { return nil }
        return turnOrder[currentTurnIndex]
    }

    /// True once every player in `turnOrder` has taken their turn.
    public var isRoomSelectionComplete: Bool {
        currentTurnIndex >= turnOrder.count
    }

    /// The current turn holder's room choice, once made — distinguishes "has
    /// not chosen yet" from "chose, and is in the 10s reading window", since
    /// `currentTurnIndex` only advances after that window elapses.
    public var currentRoomChoice: RoomVisit? {
        guard let current = currentTurnPlayerID, let last = roomVisitLog.last, last.playerID == current else {
            return nil
        }
        return last
    }

    /// Transitions into `.roomSelection`, reusing the Phase 2 arrival order as
    /// the turn order and clearing any previous round's visit log.
    public func beginRoomSelection() {
        phase = .roomSelection
        turnOrder = minigameFinishOrder
        currentTurnIndex = 0
        roomVisitLog = []
    }

    /// Records the current turn holder's room choice and returns what they
    /// found. Ignores calls from anyone other than the current turn holder,
    /// and repeat calls within the same turn (returns `nil` in both cases).
    /// Does **not** advance the turn — see `advanceRoomTurn()`.
    public func recordRoomChoice(playerID: UUID, room: RoomID) -> RoomFinding? {
        guard playerID == currentTurnPlayerID, currentRoomChoice == nil else { return nil }

        roomVisitLog.append(RoomVisit(playerID: playerID, roomID: room))

        guard let clue = roundClueAssignments[room] else { return .empty }
        guard playerID != penalizedPlayerID else { return .hiddenByPenalty }
        return .clue(clue)
    }

    /// Advances to the next player's turn. Called once the current turn
    /// holder's reading window has elapsed.
    public func advanceRoomTurn() {
        guard !isRoomSelectionComplete else { return }
        currentTurnIndex += 1
    }

    // MARK: - Round loop + Black-out event

    /// Called from the TV's "Next round" button once the notebook phase
    /// is done being reviewed. Advances to the next round, routing into the
    /// Black-out narrative beat if this is the designated round, or straight
    /// back into the normal Minigame → Rooms → Notebook cycle otherwise.
    public func beginNextRound() {
        roundNumber += 1
        if isCurrentRoundBlackout {
            reshuffleClueRoomsForBlackout()
            phase = .blackoutReveal
        } else {
            beginMinigame()
        }
    }

    /// Keeps exactly one of the 3 clues in its current room and relocates
    /// the other two to rooms that have never held a clue before.
    private func reshuffleClueRoomsForBlackout() {
        guard let keptRoom = roundClueAssignments.keys.randomElement() else { return }

        let cluesToMove = roundClueAssignments.filter { $0.key != keptRoom }.map(\.value)
        let usedRooms = Set(roundClueAssignments.keys)
        var availableRooms = RoomID.allCases.filter { !usedRooms.contains($0) }.shuffled()

        var reshuffled: [RoomID: Clue] = [keptRoom: roundClueAssignments[keptRoom]!]
        for clue in cluesToMove {
            guard let newRoom = availableRooms.popLast() else { break }
            reshuffled[newRoom] = clue
        }
        roundClueAssignments = reshuffled
    }

    /// Transitions into `.blackoutTask`, starting the (purely scenic) timer
    /// and clearing any previous completion state. For `lightRegulator`,
    /// rolls a fresh target and resets every connected player to 0.
    public func beginBlackoutTask() {
        phase = .blackoutTask
        blackoutTaskStartedAt = Date()
        blackoutTaskFinishedPlayerIDs = []

        if blackoutMinigame == .lightRegulator {
            blackoutLightTarget = Double(Int.random(in: 40...85))
            blackoutLightValues = Dictionary(uniqueKeysWithValues: players.map { ($0.id, 0.0) })
            recalculateBlackoutLightAverage()
        }
    }

    /// Records a player's completion of the Black-out emergency task,
    /// ignoring duplicates or unknown IDs.
    public func recordBlackoutTaskFinish(id: UUID) {
        guard phase == .blackoutTask,
              players.contains(where: { $0.id == id }),
              !blackoutTaskFinishedPlayerIDs.contains(id)
        else { return }

        blackoutTaskFinishedPlayerIDs.append(id)
    }

    /// True once every connected player has finished the Black-out task.
    public var allPlayersFinishedBlackoutTask: Bool {
        phase == .blackoutTask && !players.isEmpty && blackoutTaskFinishedPlayerIDs.count == players.count
    }

    /// Records a player's regulator slider value for the `lightRegulator`
    /// task and recalculates the team average. This task succeeds or fails
    /// as a team rather than individually: once the average lands within
    /// `blackoutLightTolerance` of the target, every current player is
    /// marked finished at once.
    public func updateBlackoutLightValue(playerID: UUID, value: Double) {
        guard blackoutMinigame == .lightRegulator,
              phase == .blackoutTask,
              players.contains(where: { $0.id == playerID })
        else { return }

        blackoutLightValues[playerID] = value
        recalculateBlackoutLightAverage()

        if abs(blackoutLightAverage - blackoutLightTarget) < Self.blackoutLightTolerance {
            blackoutTaskFinishedPlayerIDs = players.map(\.id)
        }
    }

    private func recalculateBlackoutLightAverage() {
        guard !blackoutLightValues.isEmpty else {
            blackoutLightAverage = 0
            return
        }
        blackoutLightAverage = blackoutLightValues.values.reduce(0, +) / Double(blackoutLightValues.count)
    }

    // MARK: - Final accusation (Phase 5)

    /// Starts a vote, unless someone else is already voting or the game
    /// isn't currently in the notebook phase — this is also what keeps a
    /// stray/delayed `.startVoting` from hijacking the phase mid-Black-out
    /// or during any other phase, since voting is only ever meant to be
    /// reachable from the notebook. Returns whether the vote was allowed to
    /// start.
    public func startVoting(playerID: UUID) -> Bool {
        guard phase == .notebook, votingPlayerID == nil else { return false }
        votingPlayerID = playerID
        phase = .voting
        return true
    }

    /// Resolves the current vote. Ignores accusations from anyone other
    /// than the player who started it. A correct accusation ends the game
    /// (`.victory`); a wrong one returns to `.notebook` with `lastAccusation`
    /// set so everyone sees the outcome. Returns whether the accusation was
    /// correct.
    @discardableResult
    public func castAccusation(playerID: UUID, suspectID: String) -> Bool {
        guard votingPlayerID == playerID else { return false }

        let correct = suspectID == culpritID
        lastAccusation = Accusation(playerID: playerID, suspectID: suspectID, wasCorrect: correct)
        votingPlayerID = nil
        phase = correct ? .victory : .notebook
        return correct
    }
}
