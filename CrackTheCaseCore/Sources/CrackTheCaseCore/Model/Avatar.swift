import Foundation

/// A preset avatar a player can pick during the lobby phase.
///
/// The raw value doubles as the SF Symbol name used to render the avatar,
/// so the UI layer can draw it directly with `Image(systemName: avatar.rawValue)`.
public enum Avatar: String, Codable, CaseIterable, Sendable, Identifiable {
    case fox = "hare.fill"
    case owl = "bird.fill"
    case cat = "cat.fill"
    case dog = "dog.fill"
    case bear = "pawprint.fill"
    case tortoise = "tortoise.fill"
    case fish = "fish.fill"
    case ladybug = "ladybug.fill"

    public var id: String { rawValue }

    /// A human-readable name shown next to the icon, e.g. in avatar pickers.
    public var displayName: String {
        switch self {
        case .fox: return "Fox"
        case .owl: return "Owl"
        case .cat: return "Cat"
        case .dog: return "Dog"
        case .bear: return "Bear"
        case .tortoise: return "Tortoise"
        case .fish: return "Fish"
        case .ladybug: return "Ladybug"
        }
    }
}
