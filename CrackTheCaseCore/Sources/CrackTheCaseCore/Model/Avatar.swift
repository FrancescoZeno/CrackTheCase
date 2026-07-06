import Foundation

/// A preset color badge auto-assigned to a player when they join the lobby.
///
/// Also reused as the "case color" for suspects (see `Suspect.color`), so the
/// same 6-color palette identifies both detectives and suspects throughout
/// the game. The UI layer maps each case to a concrete `Color`/`UIColor`
/// value — this type only carries the abstract identity, no platform color.
public enum Avatar: String, Codable, CaseIterable, Sendable, Identifiable {
    case blue
    case green
    case yellow
    case red
    case purple
    case white

    public var id: String { rawValue }

    /// A human-readable name shown next to the badge, e.g. in rosters.
    public var displayName: String {
        switch self {
        case .blue: return "Blue"
        case .green: return "Green"
        case .yellow: return "Yellow"
        case .red: return "Red"
        case .purple: return "Purple"
        case .white: return "White"
        }
    }

    /// Detective-themed emoji associated with the avatar.
    public var emoji: String {
        switch self {
        case .blue: return "🔍"
        case .green: return "☝️"
        case .yellow: return "👣"
        case .red: return "🔦"
        case .purple: return "👁️"
        case .white: return "📓"
        }
    }
}
