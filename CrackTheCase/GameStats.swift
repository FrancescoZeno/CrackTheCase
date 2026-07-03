import Foundation

/// A small local win-count leaderboard, persisted across "Play Again"
/// restarts and even full app relaunches on this Apple TV. Purely a
/// presentation nicety — never synced to clients, keyed by each player's
/// stable `PlayerIdentity` UUID (`Player.id`) so wins are correctly
/// attributed to the same person across games and reconnects.
struct GameStats: Codable {
    private static let defaultsKey = "CrackTheCase.gameStats"

    private(set) var winsByPlayerID: [UUID: Int] = [:]

    static func load(userDefaults: UserDefaults = .standard) -> GameStats {
        guard let data = userDefaults.data(forKey: defaultsKey),
              let stats = try? JSONDecoder().decode(GameStats.self, from: data)
        else { return GameStats() }
        return stats
    }

    func save(userDefaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        userDefaults.set(data, forKey: Self.defaultsKey)
    }

    mutating func recordWin(for playerID: UUID) {
        winsByPlayerID[playerID, default: 0] += 1
    }

    /// Win counts paired with a display name, sorted most wins first — for
    /// showing a leaderboard next to the current roster (`Player.nickname`
    /// isn't stored here, since a player's chosen name can change between
    /// games).
    func leaderboard(displayName: (UUID) -> String?) -> [(name: String, wins: Int)] {
        winsByPlayerID
            .compactMap { id, wins in displayName(id).map { (name: $0, wins: wins) } }
            .sorted { $0.wins > $1.wins }
    }
}
