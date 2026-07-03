import SwiftUI
import Combine

/// The `buttonMashing` turn-order minigame: mash two side buttons to push a
/// rising indicator to the top of its track before gravity pulls it back
/// down. Calls `onComplete` once the indicator reaches the top.
struct TurnButtonMashingView: View {
    let onComplete: () -> Void

    @StateObject private var engine = MashingEngine()

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                Button { engine.registerTap() } label: { EmptyView() }
                    .buttonStyle(MashingArcadeButtonStyle(title: "TAP", isDisabled: engine.phase != .playing))
                    .frame(width: geometry.size.width * 0.25)
                    .disabled(engine.phase != .playing)

                ZStack {
                    VStack {
                        Text(engine.phase == .playing || engine.phase == .finished ? String(format: "%.2f s", engine.elapsedSeconds) : "--.-- s")
                            .font(.system(size: 38, weight: .black, design: .monospaced))
                            .foregroundStyle(engine.phase == .finished ? .phoenixGold : .white)
                            .glowEffect(color: engine.phase == .finished ? .phoenixGold : .clear, radius: 10)
                            .padding(.top, 25)

                        Spacer()

                        ZStack(alignment: .bottom) {
                            Capsule()
                                .fill(Color.white.opacity(0.06))
                                .frame(width: 24, height: engine.leverLimit + 80)

                            Circle()
                                .fill(engine.phase == .finished ? Color.phoenixGold : Color.white.opacity(0.15))
                                .frame(width: 70, height: 70)
                                .overlay(
                                    Circle().stroke(Color.phoenixGold.opacity(engine.phase == .finished ? 1.0 : 0.3), lineWidth: 3)
                                )
                                .offset(y: engine.leverOffset)
                                .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.8), value: engine.leverOffset)
                        }
                        .frame(height: engine.leverLimit + 80)

                        Spacer()
                    }

                    if engine.phase == .starting {
                        ZStack {
                            Color.black.opacity(0.7).ignoresSafeArea()
                            VStack(spacing: 10) {
                                Text("PREPARING SYSTEM")
                                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.phoenixGold)
                                    .tracking(4)

                                Text("\(engine.startupCountdown)")
                                    .font(.system(size: 120, weight: .heavy, design: .rounded))
                                    .foregroundStyle(.white)
                                    .glowEffect(color: .phoenixGold, radius: 20)
                                    .animation(.spring(response: 0.3, dampingFraction: 0.5), value: engine.startupCountdown)
                            }
                        }
                    } else if engine.phase == .finished {
                        ZStack {
                            Color.black.opacity(0.85).ignoresSafeArea()
                            VStack(spacing: 20) {
                                Text("SYSTEM UNLOCKED")
                                    .font(.system(size: 28, weight: .black, design: .monospaced))
                                    .foregroundStyle(.phoenixGold)
                                    .glowEffect(color: .phoenixGold, radius: 15)

                                Text("TIME: \(String(format: "%.2f", engine.elapsedSeconds))s")
                                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.white)
                            }
                            .padding(40)
                            .background(Color.phoenixCard)
                            .cornerRadius(25)
                            .overlay(RoundedRectangle(cornerRadius: 25).stroke(Color.phoenixGold, lineWidth: 2))
                        }
                        .transition(.opacity)
                    }
                }
                .frame(width: geometry.size.width * 0.50)
                .background(Color.phoenixBackground)

                Button { engine.registerTap() } label: { EmptyView() }
                    .buttonStyle(MashingArcadeButtonStyle(title: "TAP", isDisabled: engine.phase != .playing))
                    .frame(width: geometry.size.width * 0.25)
                    .disabled(engine.phase != .playing)
            }
        }
        .edgesIgnoringSafeArea(.all)
        .onAppear {
            engine.startSetup()
            engine.onWin = onComplete
        }
        .onDisappear {
            engine.stop()
        }
    }
}

/// Physics engine for the button-mashing lever: each tap nudges the lever
/// up a fixed step, gravity continuously pulls it back down.
private final class MashingEngine: ObservableObject {
    enum GamePhase {
        case starting
        case playing
        case finished
    }

    @Published var phase: GamePhase = .starting
    @Published var startupCountdown: Int = 5
    @Published var elapsedSeconds: Double = 0.0
    @Published var leverOffset: CGFloat = 0

    let leverLimit: CGFloat = 250
    private let step: CGFloat = 16.0
    private let gravity: CGFloat = 2.0

    private var countdownTimer: Timer?
    private var gameLoopTimer: Timer?
    private var startTime: Date?

    private let tapHaptic = UIImpactFeedbackGenerator(style: .rigid)
    private let successHaptic = UINotificationFeedbackGenerator()

    /// Called once when the lever reaches the top of its track.
    var onWin: (() -> Void)?

    func startSetup() {
        tapHaptic.prepare()

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }

            if self.startupCountdown > 1 {
                self.startupCountdown -= 1
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } else {
                self.countdownTimer?.invalidate()
                self.startGame()
            }
        }
    }

    private func startGame() {
        phase = .playing
        startTime = Date()
        successHaptic.notificationOccurred(.success)

        gameLoopTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.updatePhysics()
        }
    }

    private func updatePhysics() {
        guard phase == .playing else { return }

        if let start = startTime {
            elapsedSeconds = Date().timeIntervalSince(start)
        }

        if leverOffset < 0 {
            leverOffset = min(0, leverOffset + gravity)
        }
    }

    /// Stops both timers. Must be called when the owning view disappears
    /// before a win (e.g. the round moves on because other players
    /// finished first) — otherwise the 60Hz `gameLoopTimer` keeps firing on
    /// the run loop indefinitely, since it's only ever invalidated on the
    /// win path.
    func stop() {
        countdownTimer?.invalidate()
        gameLoopTimer?.invalidate()
    }

    func registerTap() {
        guard phase == .playing else { return }

        tapHaptic.impactOccurred()

        withAnimation(.easeOut(duration: 0.05)) {
            leverOffset = max(-leverLimit, leverOffset - step)
        }

        if leverOffset <= -leverLimit {
            phase = .finished
            gameLoopTimer?.invalidate()
            successHaptic.notificationOccurred(.success)
            onWin?()
        }
    }
}

private struct MashingArcadeButtonStyle: ButtonStyle {
    let title: String
    let isDisabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed
        let activeColor = isDisabled ? Color.white.opacity(0.2) : Color.phoenixGold

        ZStack {
            Color.phoenixBackground

            VStack {
                Circle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 100, height: 100)
                    .overlay(
                        Circle().stroke(activeColor.opacity(isDisabled ? 0.0 : (isPressed ? 1.0 : 0.4)), lineWidth: isPressed ? 4 : 2)
                    )
                    .overlay(
                        Text(title)
                            .font(.system(size: 26, weight: .black, design: .monospaced))
                            .foregroundStyle(isDisabled ? Color.phoenixMuted : (isPressed ? .white : activeColor))
                            .glowEffect(color: isPressed && !isDisabled ? activeColor : .clear, radius: 8)
                    )
                    .scaleEffect(isPressed && !isDisabled ? 0.95 : 1.0)
                    .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isPressed)
            }
        }
        .contentShape(Rectangle())
    }
}
