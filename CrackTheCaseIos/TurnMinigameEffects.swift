import SwiftUI

/// Shared neon-glow shadow used by several turn-order minigames (tilt aim,
/// button mashing, valid-card swipe) for their sci-fi/hacker visual style.
extension View {
    func glowEffect(color: Color, radius: CGFloat) -> some View {
        self
            .shadow(color: color.opacity(0.8), radius: radius)
            .shadow(color: color.opacity(0.5), radius: radius / 2)
    }
}
