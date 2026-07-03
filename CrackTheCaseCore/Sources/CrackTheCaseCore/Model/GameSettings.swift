import Foundation

/// Local, per-device game settings — never synced over the network, same
/// spirit as `PlayerNickname`: what one phone or Apple TV has its sound
/// toggled to is that device's own business, not something to broadcast.
///
/// Defines the canonical `UserDefaults` keys so both app targets agree on
/// them; the SwiftUI layer typically binds to these directly via
/// `@AppStorage(GameSettings.hapticsEnabledKey)` for reactive toggles, with
/// the static readers below available to any non-View code (e.g. deciding
/// whether to fire a haptic) that needs the current value without a view.
public enum GameSettings {
    public static let musicEnabledKey = "CrackTheCaseCore.musicEnabled"
    public static let soundEffectsEnabledKey = "CrackTheCaseCore.soundEffectsEnabled"
    public static let hapticsEnabledKey = "CrackTheCaseCore.hapticsEnabled"

    /// All 3 toggles default to on — sound/music aren't implemented yet, so
    /// this only has a real effect on `hapticsEnabled` for now (see the
    /// Black-out task's vibration).
    public static func isMusicEnabled(userDefaults: UserDefaults = .standard) -> Bool {
        (userDefaults.object(forKey: musicEnabledKey) as? Bool) ?? true
    }

    public static func isSoundEffectsEnabled(userDefaults: UserDefaults = .standard) -> Bool {
        (userDefaults.object(forKey: soundEffectsEnabledKey) as? Bool) ?? true
    }

    public static func isHapticsEnabled(userDefaults: UserDefaults = .standard) -> Bool {
        (userDefaults.object(forKey: hapticsEnabledKey) as? Bool) ?? true
    }
}
