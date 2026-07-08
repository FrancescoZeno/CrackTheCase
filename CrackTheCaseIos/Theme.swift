//
//  Theme.swift
//  CrackTheCaseIos
//
//  Created by AFP PAR 049 on 01/07/2026.
//

import SwiftUI
import CrackTheCaseCore

/// Shared "Detective Vintage" palette: dark leather/walnut background, aged
/// brass accent, muted parchment-cream secondary text, and a deep bordeaux
/// for anything destructive/wrong — chosen to read as an old case file on a
/// detective's desk rather than a bright family board game. Kept identical
/// to the tvOS target's palette so both screens feel like the same game.
///
/// `phoenixGreen`/`phoenixGreenDark` and `phoenixDestructive` keep their
/// existing *semantic* roles (success/ready vs. error/wrong/danger) used
/// throughout the 12 turn minigames and 3 Black-out tasks — only their hues
/// shifted to fit this palette (a muted olive instead of a bright emerald, a
/// deep bordeaux instead of a saturated modern red). Every call site that
/// already reached for "green = good" / "red = bad" needed no changes.
extension Color {
    static let phoenixBackground = Color(red: 28 / 255, green: 22 / 255, blue: 17 / 255)
    static let phoenixCard = Color(red: 42 / 255, green: 33 / 255, blue: 24 / 255)
    static let phoenixGreen = Color(red: 90 / 255, green: 122 / 255, blue: 74 / 255)
    static let phoenixGreenDark = Color(red: 63 / 255, green: 90 / 255, blue: 56 / 255)
    static let phoenixGold = Color(red: 201 / 255, green: 154 / 255, blue: 59 / 255)
    static let phoenixMuted = Color(red: 168 / 255, green: 150 / 255, blue: 125 / 255)
    static let phoenixDestructive = Color(red: 122 / 255, green: 31 / 255, blue: 43 / 255)

    // The 6 "case colors" shared by player badges (`Avatar`) and suspect
    // evidence profiles (`Suspect.color`). Green and Red reuse the existing
    // Phoenix accents above rather than introduce near-duplicate hues.
    static let caseBlue = Color(red: 37 / 255, green: 99 / 255, blue: 235 / 255)
    static let caseYellow = Color(red: 234 / 255, green: 179 / 255, blue: 8 / 255)
    static let casePurple = Color(red: 124 / 255, green: 58 / 255, blue: 237 / 255)
    static let caseWhite = Color(red: 229 / 255, green: 231 / 255, blue: 235 / 255)
}

/// Maps each `Avatar` case (a color identity, shared by players and
/// suspects) to its concrete on-screen `Color`.
extension Avatar {
    var color: Color {
        switch self {
        case .blue: return .caseBlue
        case .green: return .phoenixGreen
        case .yellow: return .caseYellow
        case .red: return .phoenixDestructive
        case .purple: return .casePurple
        case .white: return .caseWhite
        }
    }

    /// Text color to place on top of `color` — the pale `.white` case badge
    /// needs a dark initial/icon instead of the white used everywhere else.
    var foreground: Color {
        self == .white ? .phoenixBackground : .white
    }
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

/// A plain color-filled circle showing a player's avatar emoji — the sober
/// replacement for the old SF-Symbol animal icons. Reused at every spot a
/// player's identity is shown; callers add their own stroke/overlay on top
/// for context (readiness ring, room highlight, etc.).
struct AvatarBadge: View {
    let avatar: Avatar
    var diameter: CGFloat = 56

    var body: some View {
        Circle()
            .fill(avatar.color)
            .frame(width: diameter, height: diameter)
            .overlay(
                Text(avatar.emoji)
                    .font(.system(size: diameter * 0.5))
            )
            .accessibilityLabel("\(avatar.displayName) avatar")
    }

    init(avatar: Avatar, diameter: CGFloat = 56) {
        self.avatar = avatar
        self.diameter = diameter
    }

    init(player: Player, diameter: CGFloat = 56) {
        self.init(avatar: player.avatar, diameter: diameter)
    }
}

/// The settings sheet shown on both platforms — toggles for music, sound
/// effects, and haptics. Music/effects are predisposed for a future audio
/// pass; only haptics has a real effect today, gating the Black-out task's
/// vibration.
struct SettingsSheet: View {
    @AppStorage(GameSettings.musicEnabledKey) private var musicEnabled = true
    @AppStorage(GameSettings.soundEffectsEnabledKey) private var soundEffectsEnabled = true
    @AppStorage(GameSettings.hapticsEnabledKey) private var hapticsEnabled = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Music", isOn: $musicEnabled)
                    Toggle("Sound effects", isOn: $soundEffectsEnabled)
                    Toggle("Phone vibration (Black-out)", isOn: $hapticsEnabled)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(.phoenixGold)
    }
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

/// Thin viewfinder-style corner brackets drawn at each corner of whatever
/// view it's applied to via `.overlay(CornerBrackets(...))` — the "case-file
/// dossier" visual motif used in the lobby's agent cards. Mirrors the tvOS
/// target's identical `CornerBrackets` (each target has its own copy since
/// SwiftUI view code isn't shared through `CrackTheCaseCore`).
struct CornerBrackets: View {
    var color: Color = .white.opacity(0.6)
    var length: CGFloat = 16
    var thickness: CGFloat = 2
    var inset: CGFloat = 6

    private enum Corner {
        case topLeading, topTrailing, bottomLeading, bottomTrailing
    }

    private func bracket(_ corner: Corner) -> some View {
        Path { path in
            switch corner {
            case .topLeading:
                path.move(to: CGPoint(x: 0, y: length))
                path.addLine(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: length, y: 0))
            case .topTrailing:
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: length, y: 0))
                path.addLine(to: CGPoint(x: length, y: length))
            case .bottomLeading:
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 0, y: length))
                path.addLine(to: CGPoint(x: length, y: length))
            case .bottomTrailing:
                path.move(to: CGPoint(x: length, y: 0))
                path.addLine(to: CGPoint(x: length, y: length))
                path.addLine(to: CGPoint(x: 0, y: length))
            }
        }
        .stroke(color, style: StrokeStyle(lineWidth: thickness, lineCap: .round))
        .frame(width: length, height: length)
    }

    var body: some View {
        VStack {
            HStack {
                bracket(.topLeading)
                Spacer()
                bracket(.topTrailing)
            }
            Spacer()
            HStack {
                bracket(.bottomLeading)
                Spacer()
                bracket(.bottomTrailing)
            }
        }
        .padding(inset)
        .allowsHitTesting(false)
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
