import Foundation

/// Connection lifecycle of a client (iPhone) with respect to the host (Apple TV).
public enum ClientConnectionState: Equatable, Sendable {
    /// Not browsing and not connected.
    case idle
    /// Browsing for hosts on the local network.
    case browsing
    /// An invitation was sent to a discovered host; awaiting acceptance.
    case connecting
    /// Actively connected to the host session.
    case connected
    /// Was connected but the host session ended or dropped the peer.
    case disconnected
}
