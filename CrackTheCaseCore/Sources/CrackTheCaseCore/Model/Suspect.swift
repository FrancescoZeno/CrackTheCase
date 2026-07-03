import Foundation

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
}

public enum Suspects {
    public static let all: [Suspect] = [
        Suspect(
            id: "headmaster",
            name: "Aldric Grey",
            role: "The Headmaster",
            detail: "Angrily crossed out a 9 PM appointment from last night. Says he was in his office all night.",
            icon: "graduationcap.fill"
        ),
        Suspect(
            id: "cook",
            name: "Priya Nair",
            role: "The Cook",
            detail: "The cafeteria recipe book hides a note nobody has seen before. Swears she never left the kitchen after dinner.",
            icon: "fork.knife"
        ),
        Suspect(
            id: "dorm-head",
            name: "Jonah Fitch",
            role: "Dorm Head",
            detail: "Someone left him a note on his pillow with a midnight meeting time. Claims he fell asleep early.",
            icon: "bed.double.fill"
        ),
        Suspect(
            id: "librarian",
            name: "Odalys Rook",
            role: "The Librarian",
            detail: "Knows every hidden corner of Phoenix Academy. Was in the library late, alone.",
            icon: "books.vertical.fill"
        ),
        Suspect(
            id: "caretaker",
            name: "Marcus Vale",
            role: "The Caretaker",
            detail: "Has the keys to every room in the school. Nobody has seen him since 10 PM.",
            icon: "wrench.and.screwdriver.fill"
        ),
        Suspect(
            id: "science-teacher",
            name: "Elena Cross",
            role: "Science Teacher",
            detail: "Her signature, \"E.\", shows up often in notes students pass around. Denies writing anything last night.",
            icon: "flask.fill"
        ),
    ]
}
