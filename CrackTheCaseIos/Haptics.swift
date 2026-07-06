import UIKit
import CrackTheCaseCore

/// Centralized haptic feedback for every phone screen and minigame.
///
/// Every call site used to create a brand-new `UIImpactFeedbackGenerator`/
/// `UINotificationFeedbackGenerator` and immediately trigger it — the Taptic
/// Engine needs `.prepare()` called ahead of time to actually be ready, and a
/// freshly-allocated, never-prepared generator can silently drop its first
/// (and, in fast-tap minigames creating a new instance per tap, effectively
/// every) trigger instead of vibrating. `Haptics` keeps one generator per
/// style alive for the app's lifetime, always `.prepare()`s again right
/// after firing so the next call is ready immediately, and checks
/// `GameSettings.isHapticsEnabled()` in one place instead of scattering that
/// check (or, in most call sites, forgetting it entirely) across every view.
enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let notification = UINotificationFeedbackGenerator()

    /// Primes every generator so the very first haptic of a session (or of
    /// a freshly-opened minigame) fires without the latency/drop risk of an
    /// unprepared Taptic Engine. Call once when the controller screen appears.
    static func prepareAll() {
        guard GameSettings.isHapticsEnabled() else { return }
        light.prepare()
        medium.prepare()
        heavy.prepare()
        rigid.prepare()
        soft.prepare()
        notification.prepare()
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard GameSettings.isHapticsEnabled() else { return }
        let generator = generator(for: style)
        generator.impactOccurred()
        generator.prepare()
    }

    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard GameSettings.isHapticsEnabled() else { return }
        notification.notificationOccurred(type)
        notification.prepare()
    }

    private static func generator(for style: UIImpactFeedbackGenerator.FeedbackStyle) -> UIImpactFeedbackGenerator {
        switch style {
        case .light: return light
        case .medium: return medium
        case .heavy: return heavy
        case .rigid: return rigid
        case .soft: return soft
        default: return medium
        }
    }
}
