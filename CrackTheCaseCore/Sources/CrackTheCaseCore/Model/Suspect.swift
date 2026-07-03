import Foundation

/// A physical trace investigators can find on a suspect. Each suspect's
/// `color` determines which combination of these 5 traits they carry — see
/// `Suspect.traits`.
public enum EvidenceTrait: String, Codable, Sendable, CaseIterable, Identifiable {
    case blood
    case untiedLaces
    case mud
    case tears
    case bruises

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .blood: return "Blood"
        case .untiedLaces: return "Untied laces"
        case .mud: return "Mud"
        case .tears: return "Tears"
        case .bruises: return "Bruises"
        }
    }

    /// Generic description shown when no color-specific flavor text applies.
    public var genericDescription: String {
        switch self {
        case .blood: return "The suspect has blood stains on them."
        case .untiedLaces: return "The suspect's shoelaces are untied."
        case .mud: return "Traces of mud were found on the suspect's clothing."
        case .tears: return "The suspect's clothes are covered in tears."
        case .bruises: return "The suspect has visible bruises on their skin."
        }
    }
}

/// One of the 6 suspects players narrow down using the notebook.
///
/// Static content, identical on every device — never sent over the network,
/// so it doesn't need `Codable`. Placeholder narrative content (names,
/// roles, details), meant to be swapped for the real mystery later, same
/// spirit as the placeholder room clues in `GameSession`.
public struct Suspect: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let role: String
    public let detail: String
    /// SF Symbol shown next to the suspect, echoing the room icon most
    /// associated with them.
    public let icon: String
    /// The suspect's case color — also the palette used for player badges
    /// (`Avatar`), shared for thematic consistency.
    public let color: Avatar
    /// The physical traces found on this suspect. Every color has a fixed
    /// combination of exactly 3 of the 5 possible traits.
    public let traits: Set<EvidenceTrait>

    /// Color-specific flavor text for a trait this suspect carries, falling
    /// back to the trait's generic description if this suspect doesn't have
    /// it (shouldn't normally be looked up in that case, but kept total).
    public func description(for trait: EvidenceTrait) -> String {
        guard traits.contains(trait) else { return trait.genericDescription }
        switch (color, trait) {
        case (.blue, .blood): return "Blood stains on the jacket, shirt, and hands."
        case (.blue, .untiedLaces): return "The shoelaces are untied."
        case (.green, .untiedLaces): return "The shoelaces are untied."
        case (.green, .mud): return "Mud is caked onto the clothing."
        case (.green, .tears): return "The clothing is torn in several places."
        case (.yellow, .untiedLaces): return "The shoelaces are untied."
        case (.yellow, .bruises): return "Bruises are visible on the skin."
        case (.yellow, .tears): return "The clothing is torn in several places."
        case (.red, .untiedLaces): return "The shoelaces are untied."
        case (.red, .blood): return "Blood is present, but not confined to any one spot."
        case (.red, .bruises): return "Bruises are visible on the skin."
        case (.purple, .blood): return "Blood stains are visible on the clothing."
        case (.purple, .mud): return "Mud is caked onto the clothing."
        case (.purple, .tears): return "The clothing is torn in several places."
        case (.white, .blood): return "Blood stains are visible on the clothing."
        case (.white, .bruises): return "Bruises are visible on the skin."
        case (.white, .tears): return "The clothing is torn in several places."
        default: return trait.genericDescription
        }
    }
}

public enum Suspects {
    public static let all: [Suspect] = [
        Suspect(
            id: "headmaster",
            name: "Aldric Grey",
            role: "The Headmaster",
            detail: "Angrily crossed out a 9 PM appointment from last night. Says he was in his office all night.",
            icon: "graduationcap.fill",
            color: .blue,
            traits: [.untiedLaces, .blood]
        ),
        Suspect(
            id: "cook",
            name: "Priya Nair",
            role: "The Cook",
            detail: "The cafeteria recipe book hides a note nobody has seen before. Swears she never left the kitchen after dinner.",
            icon: "fork.knife",
            color: .green,
            traits: [.untiedLaces, .mud, .tears]
        ),
        Suspect(
            id: "dorm-head",
            name: "Jonah Fitch",
            role: "Dorm Head",
            detail: "Someone left him a note on his pillow with a midnight meeting time. Claims he fell asleep early.",
            icon: "bed.double.fill",
            color: .yellow,
            traits: [.untiedLaces, .bruises, .tears]
        ),
        Suspect(
            id: "librarian",
            name: "Odalys Rook",
            role: "The Librarian",
            detail: "Knows every hidden corner of Phoenix Academy. Was in the library late, alone.",
            icon: "books.vertical.fill",
            color: .red,
            traits: [.untiedLaces, .blood, .bruises]
        ),
        Suspect(
            id: "caretaker",
            name: "Marcus Vale",
            role: "The Caretaker",
            detail: "Has the keys to every room in the school. Nobody has seen him since 10 PM.",
            icon: "wrench.and.screwdriver.fill",
            color: .purple,
            traits: [.blood, .mud, .tears]
        ),
        Suspect(
            id: "science-teacher",
            name: "Elena Cross",
            role: "Science Teacher",
            detail: "Her signature, \"E.\", shows up often in notes students pass around. Denies writing anything last night.",
            icon: "flask.fill",
            color: .white,
            traits: [.blood, .bruises, .tears]
        ),
    ]
}
