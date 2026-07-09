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

    /// Detective-themed emoji associated with the avatar. Kept for any
    /// legacy/plain-text use, but on-screen badges render `symbolName`
    /// instead — see its doc comment.
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

    /// SF Symbol equivalent of `emoji`, one per detective theme. Rendered
    /// on both platforms as a white glyph on a colored circle — the same
    /// "styled icon" treatment used for room-finding badges (see
    /// `roomFindingIconColor`/`roomFindingIcon` in each app target's
    /// `ContentView`) — instead of a plain colorful emoji glyph, so avatar
    /// badges read as part of the same visual language as the rest of the
    /// UI rather than as a system-font emoji dropped on top of it.
    public var symbolName: String {
        switch self {
        case .blue: return "magnifyingglass"
        case .green: return "hand.point.up.left.fill"
        case .yellow: return "shoeprints.fill"
        case .red: return "flashlight.on.fill"
        case .purple: return "eye.fill"
        case .white: return "book.closed.fill"
        }
    }
}
