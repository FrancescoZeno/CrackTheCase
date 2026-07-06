import SwiftUI
import CoreMotion
import Combine

/// The `shakeCharge` turn-order minigame: shake the phone to charge a
/// battery to 100%. Each detected shake adds 10%. Calls `onComplete` once
/// full — this task is entirely local (no networking of its own); arrival
/// order across players is handled the same way as every other turn
/// minigame, via `GameSession.minigameFinishOrder`.
struct TurnShakeChargeView: View {
    let onComplete: () -> Void

    @State private var progress: CGFloat = 0.0
    @State private var hasCompleted = false

    var body: some View {
        ZStack {
            Color.phoenixBackground.ignoresSafeArea()

            VStack(spacing: 20) {
                if hasCompleted {
                    VStack(spacing: 10) {
                        Text("CHARGED!")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(.phoenixGold)
                        Text("Wait for the others to finish…")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                } else {
                    VStack(spacing: 15) {
                        Text("SHAKE IT!")
                            .font(.system(size: 42, weight: .black, design: .rounded))
                            .foregroundStyle(.phoenixGold)
                            .tracking(3)

                        MinigameInstructionText(text: "Shake your phone hard until the battery bar fills up to 100%.")
                    }
                }

                ShakeChargeBatteryView(progress: progress)
                    .scaleEffect(1.2)
                    .padding(.top, 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onHyperShake {
            guard !hasCompleted else { return }
            progress = min(progress + 0.10, 1.0)
            if progress >= 1.0 {
                hasCompleted = true
                onComplete()
            }
        }
    }
}

private struct ShakeChargeBatteryView: View {
    var progress: CGFloat
    let totalBars = 10

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                HStack(spacing: 3) {
                    ForEach(0..<totalBars, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(shouldFillBar(index: index) ? barColor(for: index) : Color.white.opacity(0.12))
                            .animation(.spring(), value: progress)
                    }
                }
                .padding(6)
                .frame(width: 220, height: 75)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.phoenixGold, lineWidth: 4)
                )

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.phoenixGold)
                    .frame(width: 10, height: 25)
            }

            Text("\(Int(progress * 100))%")
                .font(.system(size: 17, weight: .bold, design: .monospaced))
                .foregroundStyle(.phoenixGold)
        }
    }

    private func shouldFillBar(index: Int) -> Bool {
        let barThreshold = CGFloat(index) / CGFloat(totalBars)
        return progress > barThreshold
    }

    private func barColor(for index: Int) -> Color {
        switch index {
        case 0, 1: return .phoenixDestructive
        case 2, 3, 4: return .phoenixGold
        case 5, 6, 7: return .caseYellow
        default: return .phoenixGreen
        }
    }
}

// MARK: - Shake detection

private final class HyperActiveShakeManager: ObservableObject {
    private let motionManager = CMMotionManager()
    private var lastUpdate: TimeInterval = 0

    /// Calibrated high enough to ignore breathing/small movements — needs a
    /// decisive flick to trigger.
    private let shakeThreshold: Double = 2.3

    private var lastXSign: Double = 0
    private var lastYSign: Double = 0
    private var lastZSign: Double = 0

    var onShakeDetected: (() -> Void)?

    init() {
        startMonitoring()
    }

    func startMonitoring() {
        guard motionManager.isAccelerometerAvailable else { return }
        motionManager.accelerometerUpdateInterval = 1.0 / 60.0

        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self, let acceleration = data?.acceleration else { return }

            let currentTime = CACurrentMediaTime()
            guard currentTime - self.lastUpdate > 0.15 else { return }

            var shakeTriggered = false

            if abs(acceleration.x) > self.shakeThreshold {
                let currentSign = acceleration.x > 0 ? 1.0 : -1.0
                if self.lastXSign != 0 && self.lastXSign != currentSign {
                    shakeTriggered = true
                }
                self.lastXSign = currentSign
            }

            if abs(acceleration.y) > self.shakeThreshold {
                let currentSign = acceleration.y > 0 ? 1.0 : -1.0
                if self.lastYSign != 0 && self.lastYSign != currentSign {
                    shakeTriggered = true
                }
                self.lastYSign = currentSign
            }

            if abs(acceleration.z) > self.shakeThreshold {
                let currentSign = acceleration.z > 0 ? 1.0 : -1.0
                if self.lastZSign != 0 && self.lastZSign != currentSign {
                    shakeTriggered = true
                }
                self.lastZSign = currentSign
            }

            if shakeTriggered {
                self.lastUpdate = currentTime
                self.lastXSign = 0
                self.lastYSign = 0
                self.lastZSign = 0
                self.onShakeDetected?()
            }
        }
    }

    /// Stops accelerometer updates. Called explicitly from `onDisappear`
    /// rather than relying solely on `deinit`, so the 60Hz motion stream
    /// stops as soon as the minigame view is dismissed instead of whenever
    /// SwiftUI happens to deallocate the `@StateObject`.
    func stopMonitoring() {
        motionManager.stopAccelerometerUpdates()
    }

    deinit {
        motionManager.stopAccelerometerUpdates()
    }
}

private struct HyperShakeModifier: ViewModifier {
    @StateObject private var shakeManager = HyperActiveShakeManager()
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear {
                shakeManager.onShakeDetected = action
            }
            .onDisappear {
                shakeManager.stopMonitoring()
            }
    }
}

private extension View {
    func onHyperShake(perform action: @escaping () -> Void) -> some View {
        modifier(HyperShakeModifier(action: action))
    }
}
