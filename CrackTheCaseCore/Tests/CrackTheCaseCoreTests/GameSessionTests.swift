import Testing
@testable import CrackTheCaseCore
import Foundation

@Suite("GameSession lobby readiness")
@MainActor
struct GameSessionTests {
    @Test("joinCode is always exactly 4 digits")
    func joinCodeIsFourDigits() {
        let session = GameSession()
        #expect(session.joinCode.count == 4)
        #expect(session.joinCode.allSatisfy { $0.isNumber })
    }

    @Test("nextAvatar avoids avatars already in use while any remain free")
    func nextAvatarAvoidsDuplicates() {
        let session = GameSession()
        for _ in 0..<Avatar.allCases.count {
            let avatar = session.nextAvatar()
            #expect(!session.players.contains { $0.avatar == avatar })
            session.upsert(Player(id: UUID(), nickname: "Player", avatar: avatar, isReady: false))
        }
        // Every avatar is now taken; nextAvatar must still return something.
        #expect(Avatar.allCases.contains(session.nextAvatar()))
    }

    @Test("canStart is false with fewer than two players, even if ready")
    func canStartRequiresMinimumPlayers() {
        let session = GameSession()
        session.upsert(Player(id: UUID(), nickname: "Ada", avatar: .fox, isReady: true))

        #expect(session.allReady)
        #expect(!session.canStart)
    }

    @Test("canStart is false until every player is ready")
    func canStartRequiresEveryoneReady() {
        let session = GameSession()
        session.upsert(Player(id: UUID(), nickname: "Ada", avatar: .fox, isReady: true))
        session.upsert(Player(id: UUID(), nickname: "Grace", avatar: .owl, isReady: false))

        #expect(!session.allReady)
        #expect(!session.canStart)
    }

    @Test("canStart is true once every player is ready and phase is lobby")
    func canStartTrueWhenAllReady() {
        let session = GameSession()
        session.upsert(Player(id: UUID(), nickname: "Ada", avatar: .fox, isReady: true))
        session.upsert(Player(id: UUID(), nickname: "Grace", avatar: .owl, isReady: true))

        #expect(session.canStart)
    }

    @Test("upsert replaces an existing player instead of duplicating")
    func upsertReplacesExistingPlayer() {
        let session = GameSession()
        let id = UUID()
        session.upsert(Player(id: id, nickname: "Ada", avatar: .fox, isReady: false))
        session.upsert(Player(id: id, nickname: "Ada Lovelace", avatar: .owl, isReady: true))

        #expect(session.players.count == 1)
        #expect(session.players[0].nickname == "Ada Lovelace")
        #expect(session.players[0].isReady)
    }

    @Test("removePlayer drops the matching player only")
    func removePlayerDropsMatch() {
        let session = GameSession()
        let keepID = UUID()
        session.upsert(Player(id: keepID, nickname: "Ada", avatar: .fox, isReady: false))
        session.upsert(Player(id: UUID(), nickname: "Grace", avatar: .owl, isReady: false))

        session.removePlayer(id: keepID)

        #expect(session.players.count == 1)
        #expect(session.players[0].nickname == "Grace")
    }

    @Test("removePlayer cascades out of minigameFinishOrder and penalizedPlayerID")
    func removePlayerCascadesMinigameState() {
        let session = GameSession()
        let first = UUID()
        let last = UUID()
        session.upsert(Player(id: first, nickname: "Ada", avatar: .fox, isReady: true))
        session.upsert(Player(id: last, nickname: "Grace", avatar: .owl, isReady: true))
        session.beginMinigame()
        session.recordMinigameFinish(id: first)
        session.recordMinigameFinish(id: last)
        #expect(session.penalizedPlayerID == last)

        session.removePlayer(id: last)

        #expect(!session.minigameFinishOrder.contains(last))
        #expect(session.penalizedPlayerID == nil)
    }

    @Test("removePlayer skips a departed player's turn instead of stalling room selection")
    func removePlayerSkipsCurrentTurn() {
        let session = GameSession()
        let first = UUID()
        let leaving = UUID()
        let last = UUID()
        session.upsert(Player(id: first, nickname: "Ada", avatar: .fox, isReady: true))
        session.upsert(Player(id: leaving, nickname: "Grace", avatar: .owl, isReady: true))
        session.upsert(Player(id: last, nickname: "Rosalind", avatar: .cat, isReady: true))
        session.beginMinigame()
        session.recordMinigameFinish(id: first)
        session.recordMinigameFinish(id: leaving)
        session.recordMinigameFinish(id: last)
        session.beginRoomSelection()
        _ = session.recordRoomChoice(playerID: first, room: .gym)
        session.advanceRoomTurn()
        #expect(session.currentTurnPlayerID == leaving)

        // The player whose turn it is disconnects mid-turn: the next player
        // should immediately become current, not get stuck forever.
        session.removePlayer(id: leaving)

        #expect(session.currentTurnPlayerID == last)
        #expect(!session.turnOrder.contains(leaving))
    }

    @Test("removePlayer of a future turn holder doesn't shift the current turn")
    func removePlayerOfFutureTurnHolder() {
        let session = GameSession()
        let first = UUID()
        let leaving = UUID()
        session.upsert(Player(id: first, nickname: "Ada", avatar: .fox, isReady: true))
        session.upsert(Player(id: leaving, nickname: "Grace", avatar: .owl, isReady: true))
        session.beginMinigame()
        session.recordMinigameFinish(id: first)
        session.recordMinigameFinish(id: leaving)
        session.beginRoomSelection()
        #expect(session.currentTurnPlayerID == first)

        session.removePlayer(id: leaving)

        // `first` hasn't taken their turn yet, so the round isn't complete —
        // removing the *future* turn holder just shrinks the turn order
        // without touching whose turn it currently is.
        #expect(session.currentTurnPlayerID == first)
        #expect(!session.turnOrder.contains(leaving))
        #expect(!session.isRoomSelectionComplete)

        _ = session.recordRoomChoice(playerID: first, room: .gym)
        session.advanceRoomTurn()
        #expect(session.isRoomSelectionComplete)
    }

    @Test("beginMinigame switches phase and clears previous round's progress")
    func beginMinigameResetsState() {
        let session = GameSession()
        let id = UUID()
        session.upsert(Player(id: id, nickname: "Ada", avatar: .fox, isReady: true))
        session.recordMinigameFinish(id: id) // no-op: still .lobby, not .minigame

        session.beginMinigame()

        #expect(session.phase == .minigame)
        #expect(session.minigameFinishOrder.isEmpty)
        #expect(session.penalizedPlayerID == nil)
        #expect(TurnMinigame.allCases.contains(session.turnMinigame))
    }

    @Test("beginMinigame rolls a turnMinigame that eventually covers every case")
    func beginMinigameRollsEveryMinigameEventually() {
        let session = GameSession()
        var seen: Set<TurnMinigame> = []
        for _ in 0..<200 {
            session.beginMinigame()
            seen.insert(session.turnMinigame)
        }
        #expect(seen == Set(TurnMinigame.allCases))
    }

    @Test("recordMinigameFinish ignores unknown players and duplicates")
    func recordMinigameFinishIgnoresInvalid() {
        let session = GameSession()
        let id = UUID()
        session.upsert(Player(id: id, nickname: "Ada", avatar: .fox, isReady: true))
        session.beginMinigame()

        session.recordMinigameFinish(id: UUID()) // unknown player
        #expect(session.minigameFinishOrder.isEmpty)

        session.recordMinigameFinish(id: id)
        session.recordMinigameFinish(id: id) // duplicate
        #expect(session.minigameFinishOrder == [id])
    }

    @Test("penalizedPlayerID is set to the last arrival only once everyone finished")
    func penalizedPlayerIsLastArrival() {
        let session = GameSession()
        let first = UUID()
        let last = UUID()
        session.upsert(Player(id: first, nickname: "Ada", avatar: .fox, isReady: true))
        session.upsert(Player(id: last, nickname: "Grace", avatar: .owl, isReady: true))
        session.beginMinigame()

        session.recordMinigameFinish(id: first)
        #expect(session.penalizedPlayerID == nil)
        #expect(!session.allPlayersFinishedMinigame)

        session.recordMinigameFinish(id: last)
        #expect(session.penalizedPlayerID == last)
        #expect(session.allPlayersFinishedMinigame)
    }

    @Test("beginRoomSelection reuses the minigame arrival order as turn order")
    func beginRoomSelectionReusesArrivalOrder() {
        let session = GameSession()
        let first = UUID()
        let second = UUID()
        session.upsert(Player(id: first, nickname: "Ada", avatar: .fox, isReady: true))
        session.upsert(Player(id: second, nickname: "Grace", avatar: .owl, isReady: true))
        session.beginMinigame()
        session.recordMinigameFinish(id: second)
        session.recordMinigameFinish(id: first)

        session.beginRoomSelection()

        #expect(session.phase == .roomSelection)
        #expect(session.turnOrder == [second, first])
        #expect(session.currentTurnPlayerID == second)
        #expect(session.roomVisitLog.isEmpty)
    }

    @Test("recordRoomChoice ignores choices from anyone but the current turn holder")
    func recordRoomChoiceIgnoresOutOfTurn() {
        let session = GameSession()
        let first = UUID()
        let second = UUID()
        session.upsert(Player(id: first, nickname: "Ada", avatar: .fox, isReady: true))
        session.upsert(Player(id: second, nickname: "Grace", avatar: .owl, isReady: true))
        session.beginMinigame()
        session.recordMinigameFinish(id: first)
        session.recordMinigameFinish(id: second)
        session.beginRoomSelection()

        let outOfTurnResult = session.recordRoomChoice(playerID: second, room: .library)

        #expect(outOfTurnResult == nil)
        #expect(session.roomVisitLog.isEmpty)
    }

    @Test("recordRoomChoice ignores a second choice within the same turn")
    func recordRoomChoiceIgnoresRepeatWithinTurn() {
        let session = GameSession()
        let id = UUID()
        session.upsert(Player(id: id, nickname: "Ada", avatar: .fox, isReady: true))
        session.beginMinigame()
        session.recordMinigameFinish(id: id)
        session.beginRoomSelection()

        _ = session.recordRoomChoice(playerID: id, room: .library)
        let secondAttempt = session.recordRoomChoice(playerID: id, room: .gym)

        #expect(secondAttempt == nil)
        #expect(session.roomVisitLog.count == 1)
        #expect(session.roomVisitLog[0].roomID == .library)
    }

    @Test("recordRoomChoice returns empty for a room without a clue")
    func recordRoomChoiceEmptyRoom() {
        let session = GameSession()
        let id = UUID()
        session.upsert(Player(id: id, nickname: "Ada", avatar: .fox, isReady: true))
        session.beginMinigame()
        session.recordMinigameFinish(id: id)
        session.beginRoomSelection()

        #expect(session.recordRoomChoice(playerID: id, room: .gym) == .empty)
    }

    @Test("recordRoomChoice reveals the clue to a non-penalized player")
    func recordRoomChoiceRevealsClue() {
        let session = GameSession()
        let first = UUID()
        let last = UUID()
        session.upsert(Player(id: first, nickname: "Ada", avatar: .fox, isReady: true))
        session.upsert(Player(id: last, nickname: "Grace", avatar: .owl, isReady: true))
        session.beginMinigame()
        session.recordMinigameFinish(id: first) // first arrival: not penalized
        session.recordMinigameFinish(id: last)
        session.beginRoomSelection()

        guard case .clue(let clue) = session.recordRoomChoice(playerID: first, room: .cafeteria) else {
            Issue.record("Expected a clue in the cafeteria")
            return
        }
        #expect(clue == session.roundClueAssignments[.cafeteria])
    }

    @Test("recordRoomChoice hides the clue from the penalized player only")
    func recordRoomChoiceHidesFromPenalizedPlayer() {
        let session = GameSession()
        let first = UUID()
        let penalized = UUID()
        session.upsert(Player(id: first, nickname: "Ada", avatar: .fox, isReady: true))
        session.upsert(Player(id: penalized, nickname: "Grace", avatar: .owl, isReady: true))
        session.beginMinigame()
        session.recordMinigameFinish(id: first)
        session.recordMinigameFinish(id: penalized) // last arrival is penalized
        #expect(session.penalizedPlayerID == penalized)

        session.beginRoomSelection()
        #expect(session.currentTurnPlayerID == first)
        _ = session.recordRoomChoice(playerID: first, room: .cafeteria)
        session.advanceRoomTurn()

        #expect(session.currentTurnPlayerID == penalized)
        #expect(session.recordRoomChoice(playerID: penalized, room: .dormitory) == .hiddenByPenalty)
    }

    @Test("advanceRoomTurn moves to the next player and completes after the last")
    func advanceRoomTurnProgressesAndCompletes() {
        let session = GameSession()
        let first = UUID()
        let second = UUID()
        session.upsert(Player(id: first, nickname: "Ada", avatar: .fox, isReady: true))
        session.upsert(Player(id: second, nickname: "Grace", avatar: .owl, isReady: true))
        session.beginMinigame()
        session.recordMinigameFinish(id: first)
        session.recordMinigameFinish(id: second)
        session.beginRoomSelection()

        _ = session.recordRoomChoice(playerID: first, room: .gym)
        #expect(!session.isRoomSelectionComplete)
        session.advanceRoomTurn()
        #expect(session.currentTurnPlayerID == second)

        _ = session.recordRoomChoice(playerID: second, room: .garden)
        session.advanceRoomTurn()
        #expect(session.isRoomSelectionComplete)
        #expect(session.currentTurnPlayerID == nil)
    }

    @Test("culpritID is always one of the 6 suspects")
    func culpritIsAKnownSuspect() {
        let session = GameSession()
        #expect(Suspects.all.contains { $0.id == session.culpritID })
    }

    @Test("startVoting rejects a request outside the notebook phase")
    func startVotingRejectsOutsideNotebook() {
        let session = GameSession()
        let id = UUID()
        session.phase = .blackoutTask

        #expect(!session.startVoting(playerID: id))
        #expect(session.phase == .blackoutTask)
        #expect(session.votingPlayerID == nil)
    }

    @Test("startVoting rejects a second vote while one is in progress")
    func startVotingRejectsConcurrentVote() {
        let session = GameSession()
        let first = UUID()
        let second = UUID()
        session.phase = .notebook

        #expect(session.startVoting(playerID: first))
        #expect(session.phase == .voting)
        #expect(!session.startVoting(playerID: second))
        #expect(session.votingPlayerID == first)
    }

    @Test("castAccusation is ignored from anyone but the current voter")
    func castAccusationIgnoresWrongPlayer() {
        let session = GameSession()
        let voter = UUID()
        let bystander = UUID()
        session.phase = .notebook
        _ = session.startVoting(playerID: voter)

        let result = session.castAccusation(playerID: bystander, suspectID: session.culpritID)

        #expect(!result)
        #expect(session.votingPlayerID == voter)
        #expect(session.lastAccusation == nil)
    }

    @Test("a correct accusation ends the game in victory")
    func castAccusationCorrectEndsGame() {
        let session = GameSession()
        let voter = UUID()
        session.phase = .notebook
        _ = session.startVoting(playerID: voter)

        let result = session.castAccusation(playerID: voter, suspectID: session.culpritID)

        #expect(result)
        #expect(session.phase == .victory)
        #expect(session.votingPlayerID == nil)
        #expect(session.lastAccusation == Accusation(playerID: voter, suspectID: session.culpritID, wasCorrect: true))
    }

    @Test("a wrong accusation returns to the notebook with the outcome recorded")
    func castAccusationWrongReturnsToNotebook() {
        let session = GameSession()
        let voter = UUID()
        let wrongSuspect = Suspects.all.first { $0.id != session.culpritID }!.id
        session.phase = .notebook
        _ = session.startVoting(playerID: voter)

        let result = session.castAccusation(playerID: voter, suspectID: wrongSuspect)

        #expect(!result)
        #expect(session.phase == .notebook)
        #expect(session.votingPlayerID == nil)
        #expect(session.lastAccusation == Accusation(playerID: voter, suspectID: wrongSuspect, wasCorrect: false))
    }

    @Test("removePlayer of the current voter unblocks everyone back to the notebook")
    func removePlayerOfVoterUnblocksGame() {
        let session = GameSession()
        let voter = UUID()
        session.upsert(Player(id: voter, nickname: "Ada", avatar: .fox, isReady: true))
        session.upsert(Player(id: UUID(), nickname: "Grace", avatar: .owl, isReady: true))
        session.upsert(Player(id: UUID(), nickname: "Rosalind", avatar: .cat, isReady: true))
        session.phase = .notebook
        _ = session.startVoting(playerID: voter)

        session.removePlayer(id: voter)

        #expect(session.votingPlayerID == nil)
        // Two players are still connected — enough to continue — so this
        // lands back on .notebook rather than .notEnoughPlayers (see the
        // dedicated tests for that transition).
        #expect(session.phase == .notebook)
    }

    // MARK: - Round loop + Black-out event

    @Test("blackoutRoundNumber is always round 3")
    func blackoutRoundNumberIsAlwaysThree() {
        for _ in 0..<10 {
            let session = GameSession()
            #expect(session.blackoutRoundNumber == 3)
        }
    }

    @Test("beginNextRound advances a non-blackout round straight into minigame")
    func beginNextRoundAdvancesNormally() {
        let session = GameSession()
        let id = UUID()
        session.upsert(Player(id: id, nickname: "Ada", avatar: .fox, isReady: true))
        session.roundNumber = 1 // round 2 isn't the Black-out round.

        session.beginNextRound()

        #expect(session.roundNumber == 2)
        #expect(session.phase == .minigame)
    }

    @Test("beginNextRound routes into the black-out reveal on the designated round")
    func beginNextRoundTriggersBlackout() {
        let session = GameSession()
        session.roundNumber = session.blackoutRoundNumber - 1

        session.beginNextRound()

        #expect(session.roundNumber == session.blackoutRoundNumber)
        #expect(session.isCurrentRoundBlackout)
        #expect(session.phase == .blackoutReveal)
    }

    @Test("beginNextRound reshuffling keeps exactly one clue in place and moves the other two to fresh rooms")
    func beginNextRoundReshufflesClues() {
        let session = GameSession()
        let originalAssignments = session.roundClueAssignments
        session.roundNumber = session.blackoutRoundNumber - 1

        session.beginNextRound()

        let newAssignments = session.roundClueAssignments
        #expect(newAssignments.count == 3)
        for clue in originalAssignments.values {
            #expect(newAssignments.values.contains(clue))
        }

        let unchangedRooms = newAssignments.filter { originalAssignments[$0.key] == $0.value }
        #expect(unchangedRooms.count == 1)

        let originalRooms = Set(originalAssignments.keys)
        let movedRooms = Set(newAssignments.keys).subtracting(originalRooms)
        #expect(movedRooms.count == 2)
    }

    @Test("beginBlackoutTask starts the timer and clears previous completions")
    func beginBlackoutTaskResetsState() {
        let session = GameSession()
        session.blackoutTaskFinishedPlayerIDs = [UUID()]

        session.beginBlackoutTask()

        #expect(session.phase == .blackoutTask)
        #expect(session.blackoutTaskStartedAt != nil)
        #expect(session.blackoutTaskFinishedPlayerIDs.isEmpty)
    }

    @Test("recordBlackoutTaskFinish ignores unknown players and duplicates")
    func recordBlackoutTaskFinishIgnoresInvalid() {
        let session = GameSession()
        let id = UUID()
        session.upsert(Player(id: id, nickname: "Ada", avatar: .fox, isReady: true))
        session.beginBlackoutTask()

        session.recordBlackoutTaskFinish(id: UUID()) // unknown player
        #expect(session.blackoutTaskFinishedPlayerIDs.isEmpty)

        session.recordBlackoutTaskFinish(id: id)
        session.recordBlackoutTaskFinish(id: id) // duplicate
        #expect(session.blackoutTaskFinishedPlayerIDs == [id])
    }

    @Test("allPlayersFinishedBlackoutTask is true only once every player has finished")
    func allPlayersFinishedBlackoutTaskTracksCompletion() {
        let session = GameSession()
        let first = UUID()
        let second = UUID()
        session.upsert(Player(id: first, nickname: "Ada", avatar: .fox, isReady: true))
        session.upsert(Player(id: second, nickname: "Grace", avatar: .owl, isReady: true))
        session.beginBlackoutTask()

        session.recordBlackoutTaskFinish(id: first)
        #expect(!session.allPlayersFinishedBlackoutTask)

        session.recordBlackoutTaskFinish(id: second)
        #expect(session.allPlayersFinishedBlackoutTask)
    }

    @Test("removePlayer cascades out of blackoutTaskFinishedPlayerIDs")
    func removePlayerCascadesBlackoutTaskState() {
        let session = GameSession()
        let id = UUID()
        session.upsert(Player(id: id, nickname: "Ada", avatar: .fox, isReady: true))
        session.beginBlackoutTask()
        session.recordBlackoutTaskFinish(id: id)

        session.removePlayer(id: id)

        #expect(!session.blackoutTaskFinishedPlayerIDs.contains(id))
    }

    @Test("blackoutMinigame is always one of the known minigames")
    func blackoutMinigameIsAKnownCase() {
        for _ in 0..<50 {
            let session = GameSession()
            #expect(BlackoutMinigame.allCases.contains(session.blackoutMinigame))
        }
    }

    @Test("updateBlackoutLightValue updates the team average and ignores unrelated minigames")
    func updateBlackoutLightValueUpdatesAverage() {
        let session = makeSession(withBlackoutMinigame: .lightRegulator)
        let first = UUID()
        let second = UUID()
        session.upsert(Player(id: first, nickname: "Ada", avatar: .fox, isReady: true))
        session.upsert(Player(id: second, nickname: "Grace", avatar: .owl, isReady: true))
        session.beginBlackoutTask()

        session.updateBlackoutLightValue(playerID: first, value: 20)
        #expect(session.blackoutLightAverage == 10) // (20 + 0) / 2

        session.updateBlackoutLightValue(playerID: second, value: 40)
        #expect(session.blackoutLightAverage == 30) // (20 + 40) / 2
    }

    @Test("updateBlackoutLightValue marks every player finished once the average matches the target")
    func updateBlackoutLightValueCompletesAsATeam() {
        let session = makeSession(withBlackoutMinigame: .lightRegulator)
        let first = UUID()
        let second = UUID()
        session.upsert(Player(id: first, nickname: "Ada", avatar: .fox, isReady: true))
        session.upsert(Player(id: second, nickname: "Grace", avatar: .owl, isReady: true))
        session.beginBlackoutTask()
        let target = session.blackoutLightTarget

        session.updateBlackoutLightValue(playerID: first, value: target)
        #expect(!session.allPlayersFinishedBlackoutTask)

        session.updateBlackoutLightValue(playerID: second, value: target)
        #expect(session.allPlayersFinishedBlackoutTask)
        #expect(Set(session.blackoutTaskFinishedPlayerIDs) == Set([first, second]))
    }

    @Test("updateBlackoutLightValue ignores unknown players")
    func updateBlackoutLightValueIgnoresUnknownPlayer() {
        let session = makeSession(withBlackoutMinigame: .lightRegulator)
        session.upsert(Player(id: UUID(), nickname: "Ada", avatar: .fox, isReady: true))
        session.beginBlackoutTask()

        session.updateBlackoutLightValue(playerID: UUID(), value: 99)

        #expect(session.blackoutLightAverage == 0)
    }

    @Test("removePlayer cascades out of the light regulator average")
    func removePlayerCascadesLightRegulatorState() {
        let session = makeSession(withBlackoutMinigame: .lightRegulator)
        let first = UUID()
        let second = UUID()
        session.upsert(Player(id: first, nickname: "Ada", avatar: .fox, isReady: true))
        session.upsert(Player(id: second, nickname: "Grace", avatar: .owl, isReady: true))
        session.beginBlackoutTask()
        session.updateBlackoutLightValue(playerID: first, value: 100)
        session.updateBlackoutLightValue(playerID: second, value: 0)
        #expect(session.blackoutLightAverage == 50)

        session.removePlayer(id: second)

        #expect(session.blackoutLightAverage == 100)
    }

    /// Keeps generating fresh sessions until one rolls the requested
    /// minigame, so tests targeting one specific Black-out task aren't
    /// flaky against the other two.
    private func makeSession(withBlackoutMinigame minigame: BlackoutMinigame) -> GameSession {
        var session = GameSession()
        while session.blackoutMinigame != minigame {
            session = GameSession()
        }
        return session
    }

    // MARK: - End-to-end: every Black-out minigame reaches completion

    @Test(
        "the Black-out round always lands on round 3, and every minigame lets the game continue once finished",
        arguments: BlackoutMinigame.allCases
    )
    func blackoutMinigameCompletesAndTheGameContinues(minigame: BlackoutMinigame) {
        let session = makeSession(withBlackoutMinigame: minigame)
        let first = UUID()
        let second = UUID()
        session.upsert(Player(id: first, nickname: "Ada", avatar: .fox, isReady: true))
        session.upsert(Player(id: second, nickname: "Grace", avatar: .owl, isReady: true))

        // Round 2 -> 3 always triggers the Black-out narrative beat.
        session.roundNumber = 2
        session.beginNextRound()
        #expect(session.roundNumber == 3)
        #expect(session.isCurrentRoundBlackout)
        #expect(session.phase == .blackoutReveal)

        session.beginBlackoutTask()
        #expect(session.phase == .blackoutTask)
        #expect(session.blackoutMinigame == minigame)
        #expect(!session.allPlayersFinishedBlackoutTask)

        switch minigame {
        case .lightRegulator:
            // Cooperative: nobody is "done" individually until the team
            // average lands on the target, at which point everyone finishes
            // at once.
            let target = session.blackoutLightTarget
            session.updateBlackoutLightValue(playerID: first, value: target)
            #expect(!session.allPlayersFinishedBlackoutTask)
            session.updateBlackoutLightValue(playerID: second, value: target)

        case .overvoltageWhack, .pistonSync:
            // Independent: each player finishes their own copy of the task.
            session.recordBlackoutTaskFinish(id: first)
            #expect(!session.allPlayersFinishedBlackoutTask)
            session.recordBlackoutTaskFinish(id: second)
        }

        #expect(session.allPlayersFinishedBlackoutTask)

        // Mirrors what the TV does automatically once everyone has
        // finished: the normal round loop picks back up.
        session.beginMinigame()
        #expect(session.phase == .minigame)
        #expect(session.roundNumber == 3)
    }

    // MARK: - Too few players mid-game

    @Test("removePlayer transitions to notEnoughPlayers when the count drops below the minimum mid-game")
    func removePlayerEndsGameWhenTooFewRemain() {
        let session = GameSession()
        let first = UUID()
        let second = UUID()
        session.upsert(Player(id: first, nickname: "Ada", avatar: .fox, isReady: true))
        session.upsert(Player(id: second, nickname: "Grace", avatar: .owl, isReady: true))
        session.beginMinigame() // mid-game, not .lobby

        session.removePlayer(id: second)

        #expect(session.players.count == 1)
        #expect(session.phase == .notEnoughPlayers)
    }

    @Test("removePlayer down to zero players in the lobby does not trigger notEnoughPlayers")
    func removePlayerInLobbyIgnoresMinimum() {
        let session = GameSession()
        let id = UUID()
        session.upsert(Player(id: id, nickname: "Ada", avatar: .fox, isReady: true))

        session.removePlayer(id: id)

        #expect(session.phase == .lobby)
    }

    // MARK: - resetToLobby (shared by "Play Again" and the notEnoughPlayers acknowledgement)

    @Test("resetToLobby returns to the lobby, re-readies no one, and re-rolls the culprit and Black-out minigame")
    func resetToLobbyResetsGameState() {
        let session = GameSession()
        let originalJoinCode = session.joinCode
        let first = UUID()
        session.upsert(Player(id: first, nickname: "Ada", avatar: .fox, isReady: true))
        session.roundNumber = 3
        session.phase = .victory
        session.lastAccusation = Accusation(playerID: first, suspectID: session.culpritID, wasCorrect: true)
        session.votingPlayerID = first

        session.resetToLobby()

        #expect(session.phase == .lobby)
        #expect(session.roundNumber == 1)
        #expect(session.players.allSatisfy { !$0.isReady })
        #expect(session.votingPlayerID == nil)
        #expect(session.lastAccusation == nil)
        #expect(session.joinCode == originalJoinCode) // never changes
        #expect(Suspects.all.contains { $0.id == session.culpritID })
    }

    @Test("resetToLobby does not clear the used turn-minigame pool")
    func resetToLobbyPreservesUsedMinigamePool() {
        let session = GameSession()
        session.upsert(Player(id: UUID(), nickname: "Ada", avatar: .fox, isReady: true))

        session.beginMinigame()
        let firstPick = session.turnMinigame

        session.phase = .victory
        session.resetToLobby()
        session.beginMinigame()

        // With only one minigame used so far out of 13, the pool isn't
        // exhausted — resetToLobby must not have cleared it, so the same
        // one can't come up again immediately.
        #expect(session.turnMinigame != firstPick)
    }

    // MARK: - Turn-minigame pool (no repeats until exhausted, then reshuffles)

    @Test("beginMinigame never repeats a turn minigame until every one has appeared")
    func beginMinigameCyclesWithoutRepeats() {
        let session = GameSession()
        var seenInThisCycle: Set<TurnMinigame> = []

        for _ in 0..<TurnMinigame.allCases.count {
            session.beginMinigame()
            #expect(!seenInThisCycle.contains(session.turnMinigame))
            seenInThisCycle.insert(session.turnMinigame)
        }

        #expect(seenInThisCycle == Set(TurnMinigame.allCases))
    }

    @Test("beginMinigame reshuffles the pool once every minigame has appeared")
    func beginMinigameReshufflesAfterExhaustion() {
        let session = GameSession()
        let totalCases = TurnMinigame.allCases.count

        // Exhaust the first full cycle.
        for _ in 0..<totalCases {
            session.beginMinigame()
        }

        // The next draw must come from a freshly-reset pool of all cases,
        // not an empty one (which would crash `randomElement()!`).
        session.beginMinigame()
        #expect(TurnMinigame.allCases.contains(session.turnMinigame))
    }
}
