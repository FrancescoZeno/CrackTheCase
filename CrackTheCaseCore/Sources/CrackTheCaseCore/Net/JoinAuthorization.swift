import Foundation

/// Whether a client has been let into the game after submitting the host's
/// join code — a lightweight access gate so a stranger on the same Wi-Fi
/// can't wander into someone else's game.
public enum JoinAuthorization: Equatable, Sendable {
    /// The code hasn't been submitted yet.
    case notRequested
    /// Submitted; awaiting the host's `joinResult`.
    case pending
    /// The host rejected the code.
    case rejected
    /// No `joinResult` arrived in time — the request may have been lost in
    /// transit. Distinct from `.rejected` so the UI can say "no response"
    /// rather than implying the code itself was wrong.
    case timedOut
    /// The host accepted the code; the client may now join with a nickname.
    case accepted
}
