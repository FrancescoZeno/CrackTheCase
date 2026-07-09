//
//  Theme.swift
//  CrackTheCase
//
//  Created by AFP PAR 049 on 01/07/2026.
//

import SwiftUI
import CrackTheCaseCore

/// Shared "Detective Vintage" palette: dark leather/walnut background, aged
/// brass accent, muted parchment-cream secondary text, and a deep bordeaux
/// for anything destructive/wrong — chosen to read as an old case file on a
/// detective's desk rather than a bright family board game. Kept identical
/// to the iOS target's palette so both screens feel like the same game.
///
/// `phoenixGreen`/`phoenixGreenDark` and `phoenixDestructive` keep their
/// existing *semantic* roles (success/ready vs. error/wrong/danger) used
/// throughout the app — only their hues shifted to fit this palette (a
/// muted olive instead of a bright emerald, a deep bordeaux instead of a
/// saturated modern red). Every call site that already reached for
/// "green = good" / "red = bad" needed no changes.
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

/// A color-filled circle showing a player's avatar as a styled SF Symbol —
/// the same white-glyph-on-colored-circle treatment used for room-finding
/// badges (see `roomFindingIconColor`/`roomFindingIcon`), rather than a
/// plain system-font emoji. Reused at every spot a player's identity is
/// shown; callers add their own stroke/overlay on top for context (readiness
/// ring, room highlight, etc.).
struct AvatarBadge: View {
    let avatar: Avatar
    var diameter: CGFloat = 56

    var body: some View {
        Circle()
            .fill(avatar.color)
            .frame(width: diameter, height: diameter)
            .overlay(
                Image(systemName: avatar.symbolName)
                    .font(.system(size: diameter * 0.42, weight: .bold))
                    .foregroundStyle(avatar.foreground)
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

/// A live "MM:SS" countdown to the whole game's `gameDeadline` (see
/// `GameSession`) — the 30 minutes investigators get before the Ambassador
/// arrives (`LORE.md`). Renders nothing while `deadline` is `nil`, i.e.
/// before round 1's minigame has actually started the clock (still in
/// `.lobby`/`.starting`/`.introVideo`/`.rules`).
struct GameClockView: View {
    let deadline: Date?

    /// Below this many seconds remaining, the readout turns urgent red
    /// instead of gold — matches `GameSession.wrongVoteTimePenalty` (5
    /// minutes), so from here a single further wrong guess could plausibly
    /// run the clock out entirely.
    private static let urgentThreshold: TimeInterval = 5 * 60

    var body: some View {
        if let deadline {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = max(0, deadline.timeIntervalSince(context.date))
                let isUrgent = remaining <= Self.urgentThreshold
                Label(Self.format(remaining), systemImage: "timer")
                    .font(.system(size: 22, weight: .black, design: .monospaced))
                    .foregroundStyle(isUrgent ? Color.phoenixDestructive : Color.phoenixGold)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.35), in: Capsule())
                    .overlay(Capsule().strokeBorder((isUrgent ? Color.phoenixDestructive : Color.phoenixGold).opacity(0.5), lineWidth: 1))
                    .padding(16)
            }
        }
    }

    private static func format(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded(.down))
        return String(format: "%02d:%02d", total / 60, total % 60)
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

            Spacer()
        }
        .padding(48)
        .frame(maxWidth: 700, maxHeight: .infinity)
        .background(Color.phoenixBackground.ignoresSafeArea())
        .tint(Color.phoenixGold)
        .onChange(of: musicEnabled) {
            AudioManager.shared.refreshMuteState()
        }
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

/// A `ButtonStyle` for primary actions on the tvOS board, built on `.plain`
/// semantics instead of `.bordered`/`.borderedProminent`. This SDK's focus
/// engine has repeatedly failed to let the Siri Remote navigate onto (or
/// off of) buttons using non-`.plain` styles — see `quitToHomeButton`'s doc
/// comment for the matching story with `.card` — while `.plain` has a clean
/// track record everywhere else in this file (the home screen's "NEW GAME"/
/// "SETTINGS" buttons, `quitToHomeButton` itself). Every primary action
/// button (victory/defeat "Play Again", "Back to lobby", the rules "Got it"/
/// "Close", the intro video "Skip") uses this instead of the system bordered
/// styles for that reason.
/// Thin viewfinder-style corner brackets drawn at each corner of whatever
/// view it's applied to via `.overlay(CornerBrackets(...))` — the shared
/// visual motif tying together the "case-file dossier" lobby (player cards,
/// the empty-lobby placeholder) and the "security camera" room board tiles.
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

struct PhoenixTVButtonStyle: PrimitiveButtonStyle {
    var tint: Color
    var cornerRadius: CGFloat = 16

    func makeBody(configuration: Configuration) -> some View {
        PhoenixTVButtonView(configuration: configuration, tint: tint, cornerRadius: cornerRadius)
    }
}

struct PhoenixTVButtonView: View {
    let configuration: PrimitiveButtonStyle.Configuration
    let tint: Color
    let cornerRadius: CGFloat
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Button(action: {
            configuration.trigger()
        }) {
            configuration.label
                .foregroundStyle(.white)
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
                .background(tint, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(isFocused ? Color.white.opacity(0.8) : Color.clear, lineWidth: 3)
                )
                .scaleEffect(isFocused ? 1.04 : 1.0)
                .animation(.easeOut(duration: 0.2), value: isFocused)
        }
        .buttonStyle(.plain)
        #if os(tvOS)
        .focusEffectDisabled()
        #endif
    }
}
