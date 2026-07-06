//
//  Theme.swift
//  CrackTheCase
//
//  Created by AFP PAR 049 on 01/07/2026.
//

import SwiftUI
import CrackTheCaseCore

/// Shared Phoenix Academy palette: felt-board green + gold on dark navy, chosen
/// to read as a friendly detective-board game rather than a gritty crime
/// scene. Kept identical to the iOS target's palette so both screens feel
/// like the same game.
extension Color {
    static let phoenixBackground = Color(red: 15 / 255, green: 23 / 255, blue: 42 / 255)
    static let phoenixCard = Color(red: 25 / 255, green: 33 / 255, blue: 52 / 255)
    static let phoenixGreen = Color(red: 21 / 255, green: 128 / 255, blue: 61 / 255)
    static let phoenixGreenDark = Color(red: 22 / 255, green: 101 / 255, blue: 52 / 255)
    static let phoenixGold = Color(red: 217 / 255, green: 119 / 255, blue: 6 / 255)
    static let phoenixMuted = Color(red: 148 / 255, green: 163 / 255, blue: 184 / 255)
    static let phoenixDestructive = Color(red: 220 / 255, green: 38 / 255, blue: 38 / 255)

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

/// A suspect's case color, labeled — e.g. "Blue case".
struct CaseColorTag: View {
    let color: Avatar
    var body: some View {
        Label("\(color.displayName) case", systemImage: "tag.fill")
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(color.color)
    }
}

/// The physical traces found on a suspect, each described in that suspect's
/// own case-color flavor text (see `Suspect.description(for:)`) rather than
/// one generic line shared by everyone with that trait.
struct EvidenceTraitList: View {
    let suspect: Suspect
    var spacing: CGFloat = 6

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(EvidenceTrait.allCases.filter { suspect.traits.contains($0) }) { trait in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(suspect.color.color)
                        .frame(width: 6, height: 6)
                        .padding(.top, 6)
                    Text(suspect.description(for: trait))
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
        }
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
        VStack(alignment: .leading, spacing: 28) {
            HStack {
                Label("Settings", systemImage: "gearshape.fill")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.phoenixMuted)
                }
                .buttonStyle(.plain)
            }

            Toggle(isOn: $musicEnabled) {
                Label("Music", systemImage: "music.note")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
            }
            Toggle(isOn: $soundEffectsEnabled) {
                Label("Sound effects", systemImage: "speaker.wave.2.fill")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
            }
            Toggle(isOn: $hapticsEnabled) {
                Label("Phone vibration (Black-out)", systemImage: "waveform")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
            }

            Text("Music and sound effects are coming soon — these toggles are ready for when they arrive.")
                .font(.system(size: 16, design: .rounded))
                .foregroundStyle(.phoenixMuted)

            Spacer()
        }
        .padding(48)
        .frame(maxWidth: 700, maxHeight: .infinity)
        .background(Color.phoenixBackground.ignoresSafeArea())
        .tint(Color.phoenixGold)
    }
}

extension View {
    /// The shared "elevated card" look for panels throughout the board: a
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
            .shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 10)
            .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 2)
    }
}
