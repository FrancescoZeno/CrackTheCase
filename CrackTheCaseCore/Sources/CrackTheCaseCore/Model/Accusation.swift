import Foundation

/// The outcome of a resolved vote — safe to broadcast to every client, since
/// it's only ever created *after* the accusing player has committed to a
/// suspect (never while they're still choosing).
public struct Accusation: Codable, Sendable, Equatable {
    public let playerID: UUID
    public let suspectID: String
    public let wasCorrect: Bool

    public init(playerID: UUID, suspectID: String, wasCorrect: Bool) {
        self.playerID = playerID
        self.suspectID = suspectID
        self.wasCorrect = wasCorrect
    }
}
