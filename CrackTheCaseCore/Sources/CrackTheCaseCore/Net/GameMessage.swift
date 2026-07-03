import Foundation

/// The full set of messages exchanged between clients (iPhone controllers)
/// and the host (Apple TV) over MultipeerConnectivity.
///
/// This is a single shared enum so both sides speak the same wire protocol
/// from one source of truth. Later milestones (minigame, rooms, notebook,
/// black-out, votes) should extend this enum rather than introduce a second
/// message type.
public enum GameMessage: Codable, Sendable, Equatable {
    // MARK: Client → Host

    /// Sent right after connecting, with the host's join code. The host
    /// replies privately with `.joinResult` — only once accepted may the
    /// client send `.join`.
    case requestToJoin(id: UUID, code: String)
    /// Sent once the join code has been accepted, with the player's
    /// persisted identity and chosen nickname. The host assigns the avatar.
    case join(id: UUID, nickname: String)
    /// Sent whenever the player edits their nickname in the lobby.
    case updateProfile(id: UUID, nickname: String)
    /// Sent when the player toggles the "Ready" button.
    case setReady(id: UUID, isReady: Bool)
    /// Sent when the player finishes their turn-order minigame.
    case finishMinigame(id: UUID)
    /// Sent when the player, on their turn, chooses a room to explore.
    case chooseRoom(id: UUID, room: RoomID)
    /// Sent when the player presses the red "Vote" button from the notebook.
    case startVoting(id: UUID)
    /// Sent by the accusing player once they've picked (and confirmed) a suspect.
    case castAccusation(id: UUID, suspectID: String)
    /// Sent when the player finishes the black-out emergency task.
    case finishBlackoutTask(id: UUID)
    /// Sent whenever the player moves their regulator slider during the
    /// `lightRegulator` black-out task.
    case updateBlackoutLightValue(id: UUID, value: Double)

    // MARK: Host → Client(s)

    /// Broadcast to all clients whenever the session state changes: roster,
    /// phase, turn-order minigame progress, room-exploration turn order, the
    /// final-accusation vote, or round/black-out progress. Never carries
    /// clue content, which suspect is actually guilty ahead of time, or the
    /// round on which the black-out will trigger — only which room each
    /// player visited (`roomVisitLog`), the outcome of a vote once resolved
    /// (`lastAccusation`), and whether the *current* round is the black-out
    /// round (`isCurrentRoundBlackout`), so it's safe for every client (and
    /// the tvOS board) to see.
    case sessionState(
        players: [Player],
        phase: GamePhase,
        minigameFinishOrder: [UUID],
        penalizedPlayerID: UUID?,
        turnOrder: [UUID],
        currentTurnIndex: Int,
        roomVisitLog: [RoomVisit],
        votingPlayerID: UUID?,
        lastAccusation: Accusation?,
        roundNumber: Int,
        isCurrentRoundBlackout: Bool,
        blackoutTaskStartedAt: Date?,
        blackoutTaskFinishedPlayerIDs: [UUID],
        blackoutMinigame: BlackoutMinigame,
        blackoutLightTarget: Double,
        blackoutLightAverage: Double,
        turnMinigame: TurnMinigame
    )
    /// Broadcast once the host transitions out of the lobby.
    case startGame
    /// Sent **only** to the player who just chose a room — never broadcast,
    /// since it may carry the actual clue text.
    case roomFinding(RoomFinding)
    /// Sent **only** to the player who just submitted a join code.
    case joinResult(accepted: Bool)
    /// Sent to a client that the host has removed from the session.
    case kicked
}

extension GameMessage {
    /// Encodes this message as JSON data suitable for
    /// `MCSession.send(_:toPeers:with:)`.
    public func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    /// Decodes a `GameMessage` received via `MCSessionDelegate`.
    public static func decode(_ data: Data) throws -> GameMessage {
        try JSONDecoder().decode(GameMessage.self, from: data)
    }
}
