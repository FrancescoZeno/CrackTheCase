import SwiftUI
import CrackTheCaseCore

/// The lobby roster screen: this player's own nickname/ready controls on
/// the left, everyone else's roster on the right.
///
/// A standalone, parameter-driven view (rather than a `private` computed
/// property reading `ContentView`'s own `@State`/`ClientConnectivityService`)
/// specifically so it can be previewed with a mock roster — see the
/// `#Preview`s below — without a live host connection. `ClientConnectivityService`'s
/// properties are `@MainActor private(set)`, settable only from within its
/// own file, so a real `client` can never be pre-populated for a preview;
/// plain value parameters are the only way to get a realistic-looking
/// lobby on screen without playing through a real multi-phone session.
struct LobbyContentView: View {
    let players: [Player]
    @Binding var nickname: String
    let isReady: Bool
    /// Called after every keystroke, mirroring the original inline
    /// `.onChange(of: nickname)` — persists the nickname locally and pushes
    /// the update to the host once already joined.
    let onNicknameChanged: () -> Void
    let onToggleReady: () -> Void

    var body: some View {
        ScrollView(.vertical) {
            HStack(alignment: .top, spacing: 24) {
                VStack(spacing: 16) {
                    profileCard
                    readyButton
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)

                if !players.isEmpty {
                    playersCard
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(20)
            // Extra top clearance so `profileCard`'s title doesn't start
            // under the floating top-leading `leaveGameButton` (36pt
            // circle + 12pt outer padding = 48pt footprint; a bit more on
            // top for real breathing room).
            .padding(.top, 56)
        }
        .scrollDismissesKeyboard(.interactively)
        .contentShape(Rectangle())
        .onTapGesture { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
    }

    /// Compact identity row instead of a big "fill this in" card: the
    /// nickname was already entered (and saved) on the join screen, so this
    /// is just a lightweight way to fix a typo, not the primary prompt.
    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AGENT ALIAS")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundStyle(.phoenixMuted)

            TextField("Your name", text: $nickname)
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundStyle(.white)
                .tint(.phoenixGold)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
                .onChange(of: nickname) { _, _ in
                    onNicknameChanged()
                }
        }
        .padding(16)
        .phoenixCardStyle(cornerRadius: 16)
        .overlay(CornerBrackets(color: .white.opacity(0.18), length: 12, thickness: 1.5, inset: 5))
    }

    private var readyButton: some View {
        Button {
            Haptics.impact(.medium)
            onToggleReady()
        } label: {
            Label(
                isReady ? "You're ready! Tap to cancel" : "Ready to investigate!",
                systemImage: isReady ? "checkmark.circle.fill" : "flag.checkered"
            )
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .frame(maxWidth: .infinity)
            .frame(height: 56)
        }
        .buttonStyle(PressableButtonStyle(tint: isReady ? .phoenixDestructive : .phoenixGreen))
        .disabled(nickname.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    private var readyCount: Int {
        players.count { $0.isReady }
    }

    /// Mirrors what the TV's header text already says, so a player gets the
    /// same "why hasn't it started yet" context on their own phone instead
    /// of only being able to infer it from the roster list — and once
    /// everyone's ready, a hint that the host's 3-2-1 countdown (shown only
    /// on the TV) is about to begin, so a "Ready" tap doesn't feel like it
    /// went nowhere.
    private var lobbyReadinessMessage: (text: String, color: Color)? {
        guard !players.isEmpty else { return nil }
        if players.count < GameSession.minimumPlayerCount {
            return ("Need at least \(GameSession.minimumPlayerCount) detectives to start", .phoenixMuted)
        }
        if readyCount == players.count {
            return ("Everyone's ready — starting any moment!", .phoenixGreen)
        }
        return ("Waiting for everyone to be ready…", .phoenixMuted)
    }

    private var playersCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("AGENT ROSTER")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(.white)

                Spacer()

                Text("\(readyCount)/\(players.count) ready")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.phoenixMuted)
            }

            if let status = lobbyReadinessMessage {
                Text(status.text)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(status.color)
            }

            VStack(spacing: 10) {
                ForEach(players) { player in
                    HStack(spacing: 12) {
                        AvatarBadge(player: player, diameter: 36)

                        Text(player.nickname)
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Spacer()

                        Text(player.isReady ? "READY" : "STANDBY")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .tracking(1.5)
                            .foregroundStyle(player.isReady ? Color.black : .phoenixMuted)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                player.isReady ? Color.phoenixGreen : Color.white.opacity(0.06),
                                in: Capsule()
                            )
                            .overlay(
                                Capsule().strokeBorder(player.isReady ? .clear : .white.opacity(0.15), lineWidth: 1)
                            )
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(20)
        .phoenixCardStyle()
        .overlay(CornerBrackets(color: .white.opacity(0.18), length: 14, thickness: 1.5, inset: 6))
    }
}

#Preview("Lobby — empty roster", traits: .landscapeRight) {
    ZStack {
        CinematicBackground().ignoresSafeArea()
        LobbyContentView(
            players: [],
            nickname: .constant("Ada"),
            isReady: false,
            onNicknameChanged: {},
            onToggleReady: {}
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Lobby — mid roster, not ready", traits: .landscapeRight) {
    ZStack {
        CinematicBackground().ignoresSafeArea()
        LobbyContentView(
            players: [
                Player(id: UUID(), nickname: "Ada", avatar: .blue, isReady: true),
                Player(id: UUID(), nickname: "Grace", avatar: .green, isReady: false),
                Player(id: UUID(), nickname: "Rosalind", avatar: .yellow, isReady: true),
            ],
            nickname: .constant("Ada"),
            isReady: true,
            onNicknameChanged: {},
            onToggleReady: {}
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Lobby — everyone ready", traits: .landscapeRight) {
    ZStack {
        CinematicBackground().ignoresSafeArea()
        LobbyContentView(
            players: [
                Player(id: UUID(), nickname: "Ada", avatar: .blue, isReady: true),
                Player(id: UUID(), nickname: "Grace", avatar: .green, isReady: true),
            ],
            nickname: .constant("Ada"),
            isReady: true,
            onNicknameChanged: {},
            onToggleReady: {}
        )
    }
    .preferredColorScheme(.dark)
}
