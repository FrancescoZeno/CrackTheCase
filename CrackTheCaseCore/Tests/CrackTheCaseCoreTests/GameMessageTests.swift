import Testing
@testable import CrackTheCaseCore
import Foundation

@Suite("GameMessage wire protocol")
struct GameMessageTests {
    @Test("join round-trips through encode/decode")
    func joinRoundTrip() throws {
        let id = UUID()
        let decoded = try GameMessage.decode(try GameMessage.join(id: id, nickname: "Ada").encoded())

        guard case .join(let decodedID, let decodedNickname) = decoded else {
            Issue.record("Expected .join, got \(decoded)")
            return
        }
        #expect(decodedID == id)
        #expect(decodedNickname == "Ada")
    }

    @Test("updateProfile round-trips through encode/decode")
    func updateProfileRoundTrip() throws {
        let id = UUID()
        let decoded = try GameMessage.decode(try GameMessage.updateProfile(id: id, nickname: "Grace").encoded())

        guard case .updateProfile(let decodedID, let decodedNickname) = decoded else {
            Issue.record("Expected .updateProfile, got \(decoded)")
            return
        }
        #expect(decodedID == id)
        #expect(decodedNickname == "Grace")
    }

    @Test("requestToJoin and joinResult round-trip")
    func joinCodeHandshakeRoundTrip() throws {
        let id = UUID()
        let request = try GameMessage.decode(try GameMessage.requestToJoin(id: id, code: "1234").encoded())
        guard case .requestToJoin(let decodedID, let decodedCode) = request else {
            Issue.record("Expected .requestToJoin, got \(request)")
            return
        }
        #expect(decodedID == id)
        #expect(decodedCode == "1234")

        #expect(
            try GameMessage.decode(try GameMessage.joinResult(accepted: true).encoded())
                == .joinResult(accepted: true)
        )
        #expect(
            try GameMessage.decode(try GameMessage.joinResult(accepted: false).encoded())
                == .joinResult(accepted: false)
        )
    }

    @Test("sessionState round-trips with players, phase, minigame, room, and vote progress")
    func sessionStateRoundTrip() throws {
        let players = [
            Player(id: UUID(), nickname: "Ada", avatar: .blue, isReady: true),
            Player(id: UUID(), nickname: "Grace", avatar: .green, isReady: false),
        ]
        let finishOrder = [players[1].id, players[0].id]
        let visits = [RoomVisit(playerID: players[1].id, roomID: .library)]
        let accusation = Accusation(playerID: players[0].id, suspectID: "cook", wasCorrect: false)
        let blackoutTaskStartedAt = Date()
        let message = GameMessage.sessionState(
            players: players,
            phase: .voting,
            minigameFinishOrder: finishOrder,
            penalizedPlayerID: players[0].id,
            turnOrder: finishOrder,
            currentTurnIndex: 1,
            roomVisitLog: visits,
            votingPlayerID: players[0].id,
            lastAccusation: accusation,
            roundNumber: 2,
            isCurrentRoundBlackout: true,
            blackoutTaskStartedAt: blackoutTaskStartedAt,
            blackoutTaskFinishedPlayerIDs: [players[1].id],
            blackoutMinigame: .lightRegulator,
            blackoutLightTarget: 62,
            blackoutLightAverage: 40,
            turnMinigame: .tiltAim
        )

        let decoded = try GameMessage.decode(try message.encoded())

        guard case .sessionState(
            let decodedPlayers, let decodedPhase, let decodedOrder, let decodedPenalized,
            let decodedTurnOrder, let decodedTurnIndex, let decodedVisits,
            let decodedVotingPlayerID, let decodedAccusation,
            let decodedRoundNumber, let decodedIsBlackout,
            let decodedBlackoutStartedAt, let decodedBlackoutFinished,
            let decodedBlackoutMinigame, let decodedBlackoutLightTarget, let decodedBlackoutLightAverage,
            let decodedTurnMinigame
        ) = decoded else {
            Issue.record("Expected .sessionState, got \(decoded)")
            return
        }
        #expect(decodedPlayers == players)
        #expect(decodedPhase == .voting)
        #expect(decodedOrder == finishOrder)
        #expect(decodedPenalized == players[0].id)
        #expect(decodedTurnOrder == finishOrder)
        #expect(decodedTurnIndex == 1)
        #expect(decodedVisits == visits)
        #expect(decodedVotingPlayerID == players[0].id)
        #expect(decodedAccusation == accusation)
        #expect(decodedRoundNumber == 2)
        #expect(decodedIsBlackout)
        #expect(decodedBlackoutStartedAt == blackoutTaskStartedAt)
        #expect(decodedBlackoutFinished == [players[1].id])
        #expect(decodedBlackoutMinigame == .lightRegulator)
        #expect(decodedBlackoutLightTarget == 62)
        #expect(decodedBlackoutLightAverage == 40)
        #expect(decodedTurnMinigame == .tiltAim)
    }

    @Test("updateBlackoutLightValue round-trips")
    func updateBlackoutLightValueRoundTrip() throws {
        let id = UUID()
        let decoded = try GameMessage.decode(try GameMessage.updateBlackoutLightValue(id: id, value: 73.5).encoded())

        guard case .updateBlackoutLightValue(let decodedID, let decodedValue) = decoded else {
            Issue.record("Expected .updateBlackoutLightValue, got \(decoded)")
            return
        }
        #expect(decodedID == id)
        #expect(decodedValue == 73.5)
    }

    @Test("finishBlackoutTask round-trips")
    func finishBlackoutTaskRoundTrip() throws {
        let id = UUID()
        let decoded = try GameMessage.decode(try GameMessage.finishBlackoutTask(id: id).encoded())

        guard case .finishBlackoutTask(let decodedID) = decoded else {
            Issue.record("Expected .finishBlackoutTask, got \(decoded)")
            return
        }
        #expect(decodedID == id)
    }

    @Test("startVoting and castAccusation round-trip")
    func votingMessagesRoundTrip() throws {
        let id = UUID()
        let votingDecoded = try GameMessage.decode(try GameMessage.startVoting(id: id).encoded())
        guard case .startVoting(let decodedID) = votingDecoded else {
            Issue.record("Expected .startVoting, got \(votingDecoded)")
            return
        }
        #expect(decodedID == id)

        let accusationDecoded = try GameMessage.decode(
            try GameMessage.castAccusation(id: id, suspectID: "librarian").encoded()
        )
        guard case .castAccusation(let decodedID2, let decodedSuspectID) = accusationDecoded else {
            Issue.record("Expected .castAccusation, got \(accusationDecoded)")
            return
        }
        #expect(decodedID2 == id)
        #expect(decodedSuspectID == "librarian")
    }

    @Test("finishMinigame round-trips")
    func finishMinigameRoundTrip() throws {
        let id = UUID()
        let decoded = try GameMessage.decode(try GameMessage.finishMinigame(id: id).encoded())

        guard case .finishMinigame(let decodedID) = decoded else {
            Issue.record("Expected .finishMinigame, got \(decoded)")
            return
        }
        #expect(decodedID == id)
    }

    @Test("chooseRoom round-trips")
    func chooseRoomRoundTrip() throws {
        let id = UUID()
        let decoded = try GameMessage.decode(try GameMessage.chooseRoom(id: id, room: .theater).encoded())

        guard case .chooseRoom(let decodedID, let decodedRoom) = decoded else {
            Issue.record("Expected .chooseRoom, got \(decoded)")
            return
        }
        #expect(decodedID == id)
        #expect(decodedRoom == .theater)
    }

    @Test("roomFinding round-trips for all three outcomes")
    func roomFindingRoundTrip() throws {
        let clue = Clue(title: "Title", text: "Text")

        #expect(try GameMessage.decode(try GameMessage.roomFinding(.empty).encoded()) == .roomFinding(.empty))
        #expect(
            try GameMessage.decode(try GameMessage.roomFinding(.clue(clue)).encoded()) == .roomFinding(.clue(clue))
        )
        #expect(
            try GameMessage.decode(try GameMessage.roomFinding(.hiddenByPenalty).encoded())
                == .roomFinding(.hiddenByPenalty)
        )
    }

    @Test("startGame and kicked round-trip with no payload")
    func payloadlessMessagesRoundTrip() throws {
        #expect(try GameMessage.decode(try GameMessage.startGame.encoded()) == .startGame)
        #expect(try GameMessage.decode(try GameMessage.kicked.encoded()) == .kicked)
    }
}
