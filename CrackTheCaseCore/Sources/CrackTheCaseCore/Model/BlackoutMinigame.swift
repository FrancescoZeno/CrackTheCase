import Foundation

/// Which emergency task plays during the Black-out round. Chosen once at
/// session creation (see `GameSession.blackoutMinigame`) so every client
/// renders the same minigame without an extra round-trip.
public enum BlackoutMinigame: String, Codable, Sendable, CaseIterable {
    /// Every player nudges their own regulator slider so the team's average
    /// output lands on the target the host announces. Succeeds or fails for
    /// every player at once — see `GameSession.updateBlackoutLightValue(playerID:value:)`.
    case lightRegulator
    /// Tap sparks before they fade. Completed independently by each player,
    /// like the normal turn-order minigame.
    case overvoltageWhack
    /// Tap each piston while it's in its green zone, then throw the lever.
    /// Completed independently by each player.
    case pistonSync
}
