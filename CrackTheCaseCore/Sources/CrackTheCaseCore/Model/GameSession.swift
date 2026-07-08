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
    /// oldest finish first. Reset each time `beginMinigame()` runs. Includes
    /// players who were skipped/timed-out via `skipMinigame(id:)`, so
    /// `allPlayersFinishedMinigame` can still become true without every
    /// player actually solving their minigame.
    public var minigameFinishOrder: [UUID] = []
    /// When the first player finished this round's minigame, `nil` before
    /// that and reset by `beginMinigame()`. The host uses this as the anchor
    /// for the skip-grace-period deadline (see `minigameSkipGracePeriod`)
    /// and broadcasts it so every phone can render the same countdown.
    public var minigameFirstFinishAt: Date?
    /// Which of the 12 turn-order minigames is being played this round,
    /// re-rolled at random every time `beginMinigame()` runs.
    public var turnMinigame: TurnMinigame = TurnMinigame.allCases.randomElement()!
    /// Turn-order minigames already played, so `beginMinigame()` cycles
    /// through all 12 once each before any repeat. Deliberately **not**
    /// cleared by `resetToLobby()` — variety keeps accumulating across
    /// "Play Again" games too, only resetting once every minigame has come
    /// up at least once since the last reset.
    private var usedTurnMinigames: Set<TurnMinigame> = []
    /// Every player penalized this round: whoever's arrival completes the
    /// group — i.e. finishes dead last, whether by actually solving the
    /// minigame or by giving up/timing out (see `recordMinigameFinish(id:)`
    /// and `skipMinigame(id:)`) — plus anyone else who gave up or timed out
    /// even earlier. Consumed during room exploration: any of these players
    /// finds their room's clue hidden. More than one player can be
    /// penalized in the same round (e.g. two people skip before the last
    /// legitimate finisher arrives).
    public var penalizedPlayerIDs: Set<UUID> = []

    /// Cumulative points earned across every round's turn-order minigame,
    /// keyed by player id — host-local only (never broadcast; the tvOS board
    /// is the only screen that shows the end-of-game ranking derived from
    /// it, same as `GameStats`' win counter). Only awarded by
    /// `recordMinigameFinish(id:)`, i.e. for actually solving the minigame —
    /// `skipMinigame(id:)` awards nothing on top of its existing clue
    /// penalty, so giving up can never out-score a slow-but-real finish.
    /// Reset once per game by `resetToLobby()`; a fresh `GameSession` (a
    /// brand-new "New Game", as opposed to "Play Again") starts empty by
    /// construction.
    public private(set) var minigameScores: [UUID: Int] = [:]

    /// Players ordered by `minigameScores`, highest first (ties keep each
    /// player's original `players` order, since `sorted(by:)` is stable).
    /// Drives the end-of-game ranking shown alongside the win leaderboard —
    /// the last player in this list is the one who receives the "PENITENZA"
    /// badge for the game as a whole.
    public var finalRanking: [Player] {
        players.sorted { (minigameScores[$0.id] ?? 0) > (minigameScores[$1.id] ?? 0) }
    }

    /// How long after the first player finishes the turn-order minigame the
    /// host waits before auto-skipping everyone still stuck — see
    /// `HostConnectivityService`'s deadline task. Also drives the on-screen
    /// countdown on both the phone and the tvOS board (as a plain
    /// `TimeInterval` rather than `Duration` so both the `Task.sleep` side
    /// and the `Date` arithmetic driving the countdown UI can use it as-is).
    public static let minigameSkipGracePeriod: TimeInterval = 15
    /// Same idea as `minigameSkipGracePeriod`, but for the Black-out
    /// emergency task — anchored to `blackoutTaskStartedAt` instead of a
    /// first-finish moment, since that task doesn't have a "first arrival"
    /// beat of its own.
    public static let blackoutSkipGracePeriod: TimeInterval = 25

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
    public var roundClueAssignments: [RoomID: Clue] = [:]

    /// Generates the starting 3 clues for a game based on the culprit's traits.
    /// The clues are placed in the same 3 fixed rooms to start, matching the
    /// original pacing before Black-out reshuffles them.
    private static func generateClues(for culpritID: String) -> [RoomID: Clue] {
        guard let suspect = Suspects.all.first(where: { $0.id == culpritID }) else { return [:] }
        let traits = Array(suspect.traits)
        var assignments: [RoomID: Clue] = [:]
        let startingRooms: [RoomID] = [.cafeteria, .dormitory, .secretaryOffice]
        for (i, trait) in traits.enumerated() {
            if i < startingRooms.count {
                assignments[startingRooms[i]] = Clue(title: trait.displayName, text: trait.genericDescription)
            }
        }
        return assignments
    }

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
    /// The last round investigators get: if round `maxRoundNumber` finishes
    /// its notebook phase with nobody having accused the actual culprit,
    /// `beginNextRound()` ends the game in `.defeat` instead of starting
    /// another round.
    public static let maxRoundNumber = 15
    /// The round on which the Black-out event triggers. Randomized 3-5 at
    /// session creation — every game gets exactly one Black-out, but players
    /// can't predict which round it'll land on.
    public let blackoutRoundNumber = Int.random(in: 3...5)
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

    /// Players who have already made a wrong accusation this round.
    public var failedAccusationPlayerIDs: Set<UUID> = []

    /// For each player who has ever made a wrong accusation, the round
    /// number during which they're barred from voting again — set to the
    /// round *after* the wrong guess in `castAccusation(playerID:suspectID:)`
    /// and checked in `startVoting(playerID:)`. Distinct from
    /// `failedAccusationPlayerIDs` (which only blocks re-voting for the rest
    /// of the *same* round a wrong guess happened in, and resets every
    /// round): this is the one-round "sit out" penalty that actually carries
    /// into the *next* round, then lifts on its own — nothing needs to
    /// explicitly clear an entry once `roundNumber` moves past it, so stale
    /// entries are harmless and left in place until `resetToLobby()`.
    public var votingBanRoundNumbers: [UUID: Int] = [:]

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
        self.roundClueAssignments = GameSession.generateClues(for: self.culpritID)
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
    /// - `penalizedPlayerIDs`, removing them if present.
    public func removePlayer(id: UUID) {
        players.removeAll { $0.id == id }
        minigameFinishOrder.removeAll { $0 == id }

        if let removedIndex = turnOrder.firstIndex(of: id) {
            turnOrder.remove(at: removedIndex)
            if removedIndex < currentTurnIndex {
                currentTurnIndex -= 1
            }
        }

        penalizedPlayerIDs.remove(id)
        minigameScores.removeValue(forKey: id)

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
        minigameFirstFinishAt = nil
        penalizedPlayerIDs = []
        minigameScores = [:]
        turnOrder = []
        currentTurnIndex = 0
        roomVisitLog = []
        roundClueAssignments = GameSession.generateClues(for: culpritID)

        votingPlayerID = nil
        lastAccusation = nil
        // A wrong accusation from the previous game's last round(s)
        // shouldn't carry into a fresh "Play Again" game and block voting
        // (or show a stale "ACCUSATION FAILED") before anyone's had a
        // chance to guess this time.
        failedAccusationPlayerIDs = []
        votingBanRoundNumbers = [:]

        blackoutTaskStartedAt = nil
        blackoutTaskFinishedPlayerIDs = []
        blackoutLightValues = [:]
        blackoutLightTarget = 0
        blackoutLightAverage = 0
        blackoutMinigame = BlackoutMinigame.allCases.randomElement()!

        culpritID = Suspects.all.randomElement()!.id
        roundClueAssignments = GameSession.generateClues(for: culpritID)
    }

    /// Picks an avatar for a newly-joining player: one not already used by a
    /// connected player, if one is free; otherwise falls back to any random
    /// avatar (more players than avatars means some duplication is
    /// unavoidable).
    public func nextAvatar() -> Avatar {
        let used = Set(players.map(\.avatar))
        let available = Avatar.allCases.filter { !used.contains($0) }
        return available.randomElement() ?? Avatar.allCases.randomElement() ?? .blue
    }

    /// True once every connected player has finished the turn-order minigame.
    public var allPlayersFinishedMinigame: Bool {
        phase == .minigame && !players.isEmpty && minigameFinishOrder.count == players.count
    }

    /// Transitions into `.minigame`, clears any previous round's progress,
    /// and rolls a fresh `turnMinigame` for this round — drawn from
    /// whichever of the 12 haven't appeared yet, so none repeats until
    /// every one of them has had a turn. Once the pool is exhausted, it
    /// reshuffles (all 12 become available again) before drawing.
    public func beginMinigame() {
        phase = .minigame
        minigameFinishOrder = []
        minigameFirstFinishAt = nil
        penalizedPlayerIDs = []

        var remaining = Set(TurnMinigame.allCases).subtracting(usedTurnMinigames)
        if remaining.isEmpty {
            usedTurnMinigames = []
            remaining = Set(TurnMinigame.allCases)
        }
        let picked = remaining.randomElement()!
        usedTurnMinigames.insert(picked)
        turnMinigame = picked
    }

    /// Records a player's arrival, ignoring duplicates or unknown IDs. Sets
    /// `minigameFirstFinishAt` the first time anyone finishes, so the host
    /// can anchor its skip-grace-period deadline (see
    /// `HostConnectivityService`) and every phone can render a matching
    /// countdown. The arrival that completes the group — whoever finishes
    /// dead last — is always penalized, on top of anyone penalized earlier
    /// via `skipMinigame(id:)`: finishing last (even by actually solving it
    /// yourself, just slower than everyone else) still costs the round's
    /// clue, exactly like before the skip-grace-period timer existed.
    public func recordMinigameFinish(id: UUID) {
        guard phase == .minigame,
              players.contains(where: { $0.id == id }),
              !minigameFinishOrder.contains(id)
        else { return }

        if minigameFirstFinishAt == nil {
            minigameFirstFinishAt = Date()
        }
        minigameFinishOrder.append(id)
        // Faster real finishes earn more points toward `finalRanking`;
        // arriving dead last still earns 1, since only `skipMinigame(id:)`
        // (giving up) scores nothing.
        minigameScores[id, default: 0] += max(players.count - minigameFinishOrder.count + 1, 1)
        if minigameFinishOrder.count == players.count {
            penalizedPlayerIDs.insert(id)
        }
    }

    /// Records that a player gave up on (or ran out the clock on) this
    /// round's turn-order minigame instead of solving it — either because
    /// they pressed "Skip" themselves or because the host's skip-grace-period
    /// timer ran out on them. Counts as an arrival for the purposes of
    /// `allPlayersFinishedMinigame`/turn order, and — like every arrival —
    /// is penalized unconditionally rather than only when it happens to be
    /// the one completing the group (see `recordMinigameFinish`'s
    /// last-arrival rule): giving up is always worse than finishing late.
    /// Ignores duplicates or unknown IDs, same as `recordMinigameFinish`.
    public func skipMinigame(id: UUID) {
        guard phase == .minigame,
              players.contains(where: { $0.id == id }),
              !minigameFinishOrder.contains(id)
        else { return }

        if minigameFirstFinishAt == nil {
            minigameFirstFinishAt = Date()
        }
        minigameFinishOrder.append(id)
        penalizedPlayerIDs.insert(id)
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

    /// The current turn holder's room choice, once made. In practice this is
    /// only ever momentarily non-nil: the host advances the turn immediately
    /// after recording a choice (see `HostConnectivityService`), so by the
    /// time observers see the updated state, `currentTurnPlayerID` has
    /// already moved to the next player. Kept mainly to guard
    /// `recordRoomChoice` against a duplicate call for the same turn.
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
        guard !roomVisitLog.contains(where: { $0.roomID == room }) else { return nil }

        roomVisitLog.append(RoomVisit(playerID: playerID, roomID: room))

        guard let clue = roundClueAssignments[room] else { return .empty }
        guard !penalizedPlayerIDs.contains(playerID) else { return .hiddenByPenalty }
        return .clue(clue)
    }

    /// Advances to the next player's turn. Called by the host immediately
    /// after recording a choice, so turns move as fast as players can pick —
    /// see `HostConnectivityService`, which holds back the actual clue
    /// reveal until every turn has gone.
    public func advanceRoomTurn() {
        guard !isRoomSelectionComplete else { return }
        currentTurnIndex += 1
    }

    // MARK: - Round loop + Black-out event

    /// Called from the TV's "Next round" button once the notebook phase
    /// is done being reviewed. Advances to the next round, routing into the
    /// Black-out narrative beat if this is the designated round, or straight
    /// back into the normal Minigame → Rooms → Notebook cycle otherwise —
    /// unless round `maxRoundNumber` has just finished without a correct
    /// accusation, in which case the game ends in `.defeat` instead of
    /// starting another round. Clears `lastAccusation` either way, so a
    /// wrong guess from the round that's ending doesn't linger on screen
    /// into the next one.
    public func beginNextRound() {
        lastAccusation = nil
        guard roundNumber < Self.maxRoundNumber else {
            phase = .defeat
            return
        }

        roundNumber += 1
        failedAccusationPlayerIDs = []
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

    /// Forces this player's Black-out task to completion — either because
    /// they pressed "Skip" themselves or because the host's skip-grace-period
    /// timer ran out on them (see `HostConnectivityService`). Unlike
    /// `skipMinigame(id:)`, this carries **no** penalty: the Black-out task
    /// is a shared emergency beat, not a competitive race, so there's no
    /// clue-visibility stake to dock. For `lightRegulator` specifically —
    /// which succeeds or fails for the whole team at once rather than per
    /// player — this force-completes every currently connected player,
    /// mirroring what `updateBlackoutLightValue(playerID:value:)` does when
    /// the team average lands on target.
    public func skipBlackoutTask(id: UUID) {
        guard phase == .blackoutTask, players.contains(where: { $0.id == id }) else { return }

        if blackoutMinigame == .lightRegulator {
            blackoutTaskFinishedPlayerIDs = players.map(\.id)
        } else if !blackoutTaskFinishedPlayerIDs.contains(id) {
            blackoutTaskFinishedPlayerIDs.append(id)
        }
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

    /// Starts a vote, unless someone else is already voting, the game isn't
    /// currently in the notebook phase, or this player is currently serving
    /// a wrong-guess penalty — either the same-round block
    /// (`failedAccusationPlayerIDs`) or the following-round "sit out"
    /// (`votingBanRoundNumbers`, see its doc comment). This is also what
    /// keeps a stray/delayed `.startVoting` from hijacking the phase
    /// mid-Black-out or during any other phase, since voting is only ever
    /// meant to be reachable from the notebook. Returns whether the vote was
    /// allowed to start.
    public func startVoting(playerID: UUID) -> Bool {
        guard phase == .notebook, votingPlayerID == nil,
              !failedAccusationPlayerIDs.contains(playerID),
              votingBanRoundNumbers[playerID] != roundNumber
        else { return false }
        votingPlayerID = playerID
        phase = .voting
        return true
    }

    /// Resolves the current vote. Ignores accusations from anyone other
    /// than the player who started it. A correct accusation ends the game
    /// (`.victory`); a wrong one returns to `.notebook` with `lastAccusation`
    /// set so everyone sees the outcome, and bars that player from voting
    /// again during the *next* round (see `votingBanRoundNumbers`). Returns
    /// whether the accusation was correct.
    @discardableResult
    public func castAccusation(playerID: UUID, suspectID: String) -> Bool {
        guard votingPlayerID == playerID else { return false }

        let correct = suspectID == culpritID
        lastAccusation = Accusation(playerID: playerID, suspectID: suspectID, wasCorrect: correct)
        votingPlayerID = nil
        if !correct {
            failedAccusationPlayerIDs.insert(playerID)
            votingBanRoundNumbers[playerID] = roundNumber + 1
        }
        phase = correct ? .victory : .notebook
        return correct
    }
}
