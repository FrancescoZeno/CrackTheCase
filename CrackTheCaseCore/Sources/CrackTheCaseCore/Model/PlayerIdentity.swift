import Foundation

/// Persists a stable player `UUID` across app launches and reconnects.
///
/// The transport layer (MultipeerConnectivity's `MCPeerID`) is regenerated
/// per session and is not a reliable player identity, so the client app
/// stores its own UUID locally and sends it in `GameMessage.join`.
public enum PlayerIdentity {
    private static let defaultsKey = "CrackTheCaseCore.playerID"

    /// Returns the persisted player UUID, creating and storing one on first use.
    public static func current(userDefaults: UserDefaults = .standard) -> UUID {
        if let stored = userDefaults.string(forKey: defaultsKey), let id = UUID(uuidString: stored) {
            return id
        }
        let newID = UUID()
        userDefaults.set(newID.uuidString, forKey: defaultsKey)
        return newID
    }
}

/// Persists the player's chosen nickname across app launches, so returning
/// players don't have to retype it every game — only the join code (which
/// the host regenerates every session) still needs entering.
public enum PlayerNickname {
    private static let defaultsKey = "CrackTheCaseCore.playerNickname"

    /// The last nickname the player used, if any.
    public static func saved(userDefaults: UserDefaults = .standard) -> String? {
        userDefaults.string(forKey: defaultsKey)
    }

    /// Stores `nickname` for next launch. No-ops for blank input so a
    /// half-typed field never clobbers a previously saved name.
    public static func save(_ nickname: String, userDefaults: UserDefaults = .standard) {
        let trimmed = nickname.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        userDefaults.set(trimmed, forKey: defaultsKey)
    }
}
