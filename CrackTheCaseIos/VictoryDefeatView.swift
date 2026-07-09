import SwiftUI
import CrackTheCaseCore

/// Shown once someone accuses the actual culprit.
///
/// A standalone, parameter-driven view (rather than a `private` computed
/// property reading `ContentView`'s own `ClientConnectivityService`)
/// specifically so it can be previewed — see the `#Preview`s below —
/// without a live host connection.
struct VictoryView: View {
    let lastAccusation: Accusation?
    let players: [Player]
    let onBackToHome: () -> Void

    var body: some View {
        LandscapeStatusView(icon: "trophy.fill") {
            Text("CASE SOLVED!")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)

            if let lastAccusation {
                let winnerName = players.first { $0.id == lastAccusation.playerID }?.nickname ?? "A detective"
                let culpritName = Suspects.all.first { $0.id == lastAccusation.suspectID }?.name ?? "the culprit"
                Text("\(winnerName) exposed \(culpritName) and wins the scholarship!")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }

            BackToHomeButton(onTap: onBackToHome)
        }
    }
}

/// Shown once `GameSession.maxRoundNumber` rounds pass without anyone
/// naming the real culprit.
struct DefeatView: View {
    let onBackToHome: () -> Void

    var body: some View {
        LandscapeStatusView(icon: "hourglass.tophalf.fill", iconColor: .phoenixDestructive) {
            Text("CASE UNSOLVED")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)

            Text("\(GameSession.maxRoundNumber) rounds have passed and nobody named the real culprit. Everyone loses.")
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)

            BackToHomeButton(onTap: onBackToHome)
        }
    }
}

/// Lets a player leave the finished game on their own, independent of
/// whatever the host does next (replay for the rest of the group, back to
/// the lobby, …) — disconnects this phone's session and returns to the
/// home screen, where "JOIN A ROOM" and "SETTINGS" live. Shared by
/// `VictoryView`/`DefeatView`; the actual disconnect+navigation happens in
/// `onTap`, supplied by `ContentView`.
struct BackToHomeButton: View {
    let onTap: () -> Void

    var body: some View {
        Button {
            Haptics.impact(.medium)
            onTap()
        } label: {
            Label("Back to Home", systemImage: "house.fill")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
    }
}

#Preview("Victory", traits: .landscapeRight) {
    let winnerID = UUID()
    ZStack {
        CinematicBackground().ignoresSafeArea()
        VictoryView(
            lastAccusation: Accusation(playerID: winnerID, suspectID: Suspects.all[0].id, wasCorrect: true),
            players: [Player(id: winnerID, nickname: "Ada", avatar: .blue, isReady: true)],
            onBackToHome: {}
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Defeat", traits: .landscapeRight) {
    ZStack {
        CinematicBackground().ignoresSafeArea()
        DefeatView(onBackToHome: {})
    }
    .preferredColorScheme(.dark)
}
