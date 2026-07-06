import SwiftUI
import CrackTheCaseCore

#if DEBUG
/// Developer-only harness for previewing every turn-order and Black-out
/// minigame without needing a live host session, two connected phones, and
/// however many rounds it takes for that particular minigame to come up.
/// Entirely wrapped in `#if DEBUG` — stripped from release builds, so
/// there's no way a player can stumble into it or see it in the lobby.
struct MinigameDebugMenuView: View {
    /// Reused so `.lightRegulator` (the one Black-out task that reads live
    /// session state instead of just taking a completion closure) has
    /// something to bind to — it won't reflect a real target/average
    /// without a connected host, but it renders and its slider is fully
    /// interactive.
    let client: ClientConnectivityService
    @Environment(\.dismiss) private var dismiss
    @State private var selection: DebugMinigameSelection?

    var body: some View {
        NavigationStack {
            List {
                Section("Turn-order minigames") {
                    ForEach(TurnMinigame.allCases, id: \.self) { minigame in
                        debugRow(minigame.displayTitle) { selection = .turn(minigame) }
                    }
                }
                Section {
                    ForEach(BlackoutMinigame.allCases, id: \.self) { minigame in
                        debugRow(minigame.displayTitle) { selection = .blackout(minigame) }
                    }
                } header: {
                    Text("Black-out minigames")
                } footer: {
                    Text("Debug build only — lets you jump straight into any minigame to check it without waiting for it to come up in a real game.")
                }
            }
            .navigationTitle("Minigame Debug Menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(.phoenixGold)
        .fullScreenCover(item: $selection) { selection in
            MinigameDebugPlayView(selection: selection, client: client)
        }
    }

    private func debugRow(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "play.circle.fill")
                    .foregroundStyle(.phoenixGold)
            }
        }
    }
}

/// Which minigame the debug menu is about to (or currently) present.
/// `Identifiable` so it can drive `.fullScreenCover(item:)` directly.
private enum DebugMinigameSelection: Identifiable, Hashable {
    case turn(TurnMinigame)
    case blackout(BlackoutMinigame)

    var id: String {
        switch self {
        case .turn(let minigame): return "turn-\(minigame.rawValue)"
        case .blackout(let minigame): return "blackout-\(minigame.rawValue)"
        }
    }
}

/// Full-screen host for a single minigame, standing in for the real
/// `activeTurnMinigameView`/`blackoutTaskView` dispatch in `ContentView` —
/// same views, same `onComplete` wiring, just reachable on demand instead of
/// only when the host actually rolls that minigame. A floating close button
/// and completion toast sit on top since there's no real game session
/// driving this screen's lifecycle.
private struct MinigameDebugPlayView: View {
    let selection: DebugMinigameSelection
    let client: ClientConnectivityService
    @Environment(\.dismiss) private var dismiss
    @State private var didComplete = false

    var body: some View {
        ZStack(alignment: .top) {
            content

            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.white, .black.opacity(0.6))
                }
                .buttonStyle(.plain)

                Spacer()

                if didComplete {
                    Label("Completed!", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.phoenixGreen, in: Capsule())
                        .transition(.opacity)
                }
            }
            .padding(16)
        }
        .animation(.easeInOut, value: didComplete)
        .statusBarHidden()
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .turn(let minigame):
            turnView(for: minigame)
        case .blackout(let minigame):
            blackoutView(for: minigame)
        }
    }

    @ViewBuilder
    private func turnView(for minigame: TurnMinigame) -> some View {
        switch minigame {
        case .numberMemory: TurnNumberMemoryView(onComplete: markComplete)
        case .holdRelease: TurnHoldReleaseView(onComplete: markComplete)
        case .tapInOrder: TurnTapInOrderView(onComplete: markComplete)
        case .magneticRings: TurnMagneticRingsView(onComplete: markComplete)
        case .shakeCharge: TurnShakeChargeView(onComplete: markComplete)
        case .swipeCardPace: TurnSwipeCardPaceView(onComplete: markComplete)
        case .crimeMemoryMatch: TurnCrimeMemoryMatchView(onComplete: markComplete)
        case .captchaReveal: TurnCaptchaRevealView(onComplete: markComplete)
        case .tiltAim: TurnTiltAimView(onComplete: markComplete)
        case .buttonMashing: TurnButtonMashingView(onComplete: markComplete)
        case .scratchPin: TurnScratchPinView(onComplete: markComplete)
        case .keyFitting: TurnKeyFittingView(onComplete: markComplete)
        case .validCardSwipe: TurnValidCardSwipeView(onComplete: markComplete)
        }
    }

    @ViewBuilder
    private func blackoutView(for minigame: BlackoutMinigame) -> some View {
        switch minigame {
        case .lightRegulator:
            // No `onComplete` to hook — this task succeeds for the whole
            // team via `GameSession.updateBlackoutLightValue`, which needs
            // a real connected host to compute the shared average. Renders
            // and its slider is interactive; it just won't reach 100%
            // team-average completion without one.
            BlackoutLightRegulatorView(client: client)
        case .overvoltageWhack:
            BlackoutOvervoltageWhackView(onComplete: markComplete)
        case .pistonSync:
            BlackoutPistonSyncView(onComplete: markComplete)
        }
    }

    private func markComplete() {
        didComplete = true
    }
}

#endif
