import Foundation

/// One of the 9 rooms at Phoenix Academy players can explore.
///
/// Names and icons are placeholder content for the mechanic (turn-based
/// exploration + clue reveal), meant to be swapped for the real story later —
/// same spirit as the placeholder "Done!" minigame button.
public enum RoomID: String, Codable, Sendable, CaseIterable, Identifiable {
    case library
    case assemblyHall
    case cafeteria
    case gym
    case dormitory
    case computerLab
    case scienceLab
    case secretaryOffice
    case studyHall

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .library: return "Library"
        case .assemblyHall: return "Assembly Hall"
        case .cafeteria: return "Cafeteria"
        case .gym: return "Gym"
        case .dormitory: return "Dormitory"
        case .computerLab: return "Computer Lab"
        case .scienceLab: return "Science Lab"
        case .secretaryOffice: return "Secretary Office"
        case .studyHall: return "Study Hall"
        }
    }

    /// SF Symbol used to represent this room on both tvOS and iOS.
    public var icon: String {
        switch self {
        case .library: return "books.vertical.fill"
        case .assemblyHall: return "theatermasks.fill"
        case .cafeteria: return "fork.knife"
        case .gym: return "figure.run"
        case .dormitory: return "bed.double.fill"
        case .computerLab: return "desktopcomputer"
        case .scienceLab: return "flask.fill"
        case .secretaryOffice: return "briefcase.fill"
        case .studyHall: return "book.fill"
        }
    }

    /// Asset catalog imageset name for this room's cover photo, shared by
    /// both app targets — see `stanze_copertina_scelte/` for the source
    /// photos and `copy_assets.sh` for how they're placed into each
    /// target's `Assets.xcassets`.
    public var coverAsset: String { rawValue }

    /// Asset catalog imageset name for this room's "clue scene" photo —
    /// shown when a player explores this room, regardless of whether it
    /// actually holds a clue this game. See `stanze_indizzi/` for the source
    /// photos and `copy_room_clue_photos.sh` for how they're placed into
    /// each target's `Assets.xcassets`. Suffixed `"Clue"` so this doesn't
    /// collide with `coverAsset`'s imageset in the same catalog.
    public var clueAsset: String { rawValue + "Clue" }
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
