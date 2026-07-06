import Foundation

/// One of the 9 rooms at Phoenix Academy players can explore.
///
/// Names and icons are placeholder content for the mechanic (turn-based
/// exploration + clue reveal), meant to be swapped for the real story later —
/// same spirit as the placeholder "Done!" minigame button.
public enum RoomID: String, Codable, Sendable, CaseIterable, Identifiable {
    case cafeteria
    case dormitory
    case library
    case scienceLab
    case gym
    case musicRoom
    case headmasterOffice
    case garden
    case theater

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .cafeteria: return "Cafeteria"
        case .dormitory: return "Dormitory"
        case .library: return "Library"
        case .scienceLab: return "Science Lab"
        case .gym: return "Gym"
        case .musicRoom: return "Computer Lab"
        case .headmasterOffice: return "Front Office"
        case .garden: return "Study Hall"
        case .theater: return "Auditorium"
        }
    }

    /// SF Symbol used to represent this room on both tvOS and iOS.
    public var icon: String {
        switch self {
        case .cafeteria: return "fork.knife"
        case .dormitory: return "bed.double.fill"
        case .library: return "books.vertical.fill"
        case .scienceLab: return "flask.fill"
        case .gym: return "figure.run"
        case .musicRoom: return "desktopcomputer"
        case .headmasterOffice: return "briefcase.fill"
        case .garden: return "book.fill"
        case .theater: return "theatermasks.fill"
        }
    }
}

/// A clue found in a room. Placeholder narrative content — swap `title`/`text`
/// for the real mystery when it's written. Which room currently holds a given
/// clue is tracked separately (see `GameSession.roundClueAssignments`), since
/// the Black-out event can move a clue to a new room mid-game.
public struct Clue: Codable, Sendable, Equatable {
    public let title: String
    public let text: String

    public init(title: String, text: String) {
        self.title = title
        self.text = text
    }
}

/// What a player sees on their phone after choosing a room for their turn.
public enum RoomFinding: Codable, Sendable, Equatable {
    /// The room had no clue this round.
    case empty
    /// The room had a clue, and this player is allowed to see it.
    case clue(Clue)
    /// The room had a clue, but this player is serving the minigame
    /// penalty, so it stays hidden from them.
    case hiddenByPenalty
}

/// A public record of "who explored which room" — safe to broadcast to every
/// client and shown on the tvOS board, since it never reveals what (if
/// anything) that player actually found there.
public struct RoomVisit: Codable, Sendable, Equatable {
    public let playerID: UUID
    public let roomID: RoomID

    public init(playerID: UUID, roomID: RoomID) {
        self.playerID = playerID
        self.roomID = roomID
    }
}
