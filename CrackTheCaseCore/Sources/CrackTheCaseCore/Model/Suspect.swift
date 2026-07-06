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
        return trait.genericDescription
    }
}

public enum Suspects {
    public static let all: [Suspect] = [
        Suspect(
            id: "headmaster",
            name: "Blue",
            role: "Suspect",
            detail: "A suspect in the case.",
            icon: "person.fill",
            color: .blue,
            traits: [.untiedLaces, .blood]
        ),
        Suspect(
            id: "cook",
            name: "Green",
            role: "Suspect",
            detail: "A suspect in the case.",
            icon: "person.fill",
            color: .green,
            traits: [.untiedLaces, .mud, .tears]
        ),
        Suspect(
            id: "dorm-head",
            name: "Yellow",
            role: "Suspect",
            detail: "A suspect in the case.",
            icon: "person.fill",
            color: .yellow,
            traits: [.untiedLaces, .bruises, .tears]
        ),
        Suspect(
            id: "librarian",
            name: "Red",
            role: "Suspect",
            detail: "A suspect in the case.",
            icon: "person.fill",
            color: .red,
            traits: [.untiedLaces, .blood, .bruises]
        ),
        Suspect(
            id: "caretaker",
            name: "Purple",
            role: "Suspect",
            detail: "A suspect in the case.",
            icon: "person.fill",
            color: .purple,
            traits: [.blood, .mud, .tears]
        ),
        Suspect(
            id: "science-teacher",
            name: "White",
            role: "Suspect",
            detail: "A suspect in the case.",
            icon: "person.fill",
            color: .white,
            traits: [.blood, .bruises, .tears]
        ),
    ]
}
