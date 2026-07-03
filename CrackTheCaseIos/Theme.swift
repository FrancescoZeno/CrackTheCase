//
//  Theme.swift
//  CrackTheCaseIos
//
//  Created by AFP PAR 049 on 01/07/2026.
//

import SwiftUI

/// Shared Phoenix Academy palette: felt-board green + gold on dark navy, chosen
/// to read as a friendly detective-board game rather than a gritty crime
/// scene. Kept identical to the tvOS target's palette so both screens feel
/// like the same game.
extension Color {
    static let phoenixBackground = Color(red: 15 / 255, green: 23 / 255, blue: 42 / 255)
    static let phoenixCard = Color(red: 25 / 255, green: 33 / 255, blue: 52 / 255)
    static let phoenixGreen = Color(red: 21 / 255, green: 128 / 255, blue: 61 / 255)
    static let phoenixGreenDark = Color(red: 22 / 255, green: 101 / 255, blue: 52 / 255)
    static let phoenixGold = Color(red: 217 / 255, green: 119 / 255, blue: 6 / 255)
    static let phoenixMuted = Color(red: 148 / 255, green: 163 / 255, blue: 184 / 255)
    static let phoenixDestructive = Color(red: 220 / 255, green: 38 / 255, blue: 38 / 255)
}

// Mirrors how SwiftUI exposes `.red`/`.blue` etc. as `ShapeStyle` statics, so
// `.phoenixGold` etc. also resolve as shorthand in `foregroundStyle`/`tint`/
// `strokeBorder` contexts, not just wherever a concrete `Color` is expected.
extension ShapeStyle where Self == Color {
    static var phoenixBackground: Color { .phoenixBackground }
    static var phoenixCard: Color { .phoenixCard }
    static var phoenixGreen: Color { .phoenixGreen }
    static var phoenixGreenDark: Color { .phoenixGreenDark }
    static var phoenixGold: Color { .phoenixGold }
    static var phoenixMuted: Color { .phoenixMuted }
    static var phoenixDestructive: Color { .phoenixDestructive }
}

extension View {
    /// The shared "elevated card" look for panels throughout the app: a
    /// dark surface with a subtle top highlight and a layered drop shadow,
    /// so panels read as physically raised instead of flat color blocks.
    func phoenixCardStyle(cornerRadius: CGFloat = 20) -> some View {
        self
            .background(Color.phoenixCard, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.14), .white.opacity(0.02)], startPoint: .top, endPoint: .bottom),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.35), radius: 14, x: 0, y: 8)
            .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 1)
    }
}

/// A `ButtonStyle` giving primary actions a soft press-down "squish" (scale
/// + darken + shadow flattening) instead of the flat system default, so
/// tappable surfaces feel physical rather than a plain color rectangle.
struct PressableButtonStyle: ButtonStyle {
    var tint: Color
    var cornerRadius: CGFloat = 16

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(tint, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(configuration.isPressed ? 0.05 : 0.18), lineWidth: 1)
            )
            .shadow(
                color: .black.opacity(configuration.isPressed ? 0.15 : 0.35),
                radius: configuration.isPressed ? 4 : 10,
                x: 0,
                y: configuration.isPressed ? 2 : 6
            )
            .brightness(configuration.isPressed ? -0.06 : 0)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
