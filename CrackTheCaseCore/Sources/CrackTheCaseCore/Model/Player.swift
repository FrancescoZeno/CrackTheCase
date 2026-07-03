import Foundation

/// A player connected to the game, as seen by both the host (Apple TV) and
/// every client (iPhone).
///
/// `id` is generated and persisted client-side (see `PlayerIdentity`) so a
/// player keeps the same identity across reconnects within a session; it is
/// unrelated to the transport-level `MCPeerID` used by MultipeerConnectivity.
public struct Player: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var nickname: String
    public var avatar: Avatar
    public var isReady: Bool

    public init(id: UUID, nickname: String, avatar: Avatar, isReady: Bool = false) {
        self.id = id
        self.nickname = nickname
        self.avatar = avatar
        self.isReady = isReady
    }
}
