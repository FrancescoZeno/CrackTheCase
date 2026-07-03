import SwiftUI

/// The `holdRelease` turn-order minigame: hold to fill a circular gauge and
/// release the instant it's full. Releasing too early or too late drains
/// the gauge and the player must start over. Calls `onComplete` once
/// released within the success window.
struct TurnHoldReleaseView: View {
    let onComplete: () -> Void

    @State private var isPressing = false
    @State private var scanProgress: Double = 0.0
    @State private var feedbackMessage = "Hold to scan"
    @State private var feedbackColor: Color = .white
    @State private var hasCompleted = false

    private let scanDuration: TimeInterval = 3.0
    private let drainDuration: TimeInterval = 1.5
    private let timerInterval: TimeInterval = 1.0 / 60.0

    @State private var timer: Timer?

    var body: some View {
        ZStack {
            Color.phoenixBackground.ignoresSafeArea()

            HStack(spacing: 20) {
                VStack(spacing: 25) {
                    Text("Thumb Sensor")
                        .font(.largeTitle)
                        .bold()
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    VStack(spacing: 12) {
                        Text(feedbackMessage)
                            .font(.title3)
                            .foregroundStyle(feedbackColor)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                            .frame(height: 60)

                        Text(feedbackStatusSubtitle)
                            .font(.headline)
                            .foregroundStyle(.phoenixMuted)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.leading, 20)

                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.15), lineWidth: 10)
                        .frame(width: 180, height: 180)

                    Circle()
                        .trim(from: 0.0, to: scanProgress)
                        .stroke(
                            AngularGradient(colors: [.phoenixGold, .phoenixGreen, .phoenixGold], center: .center),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .frame(width: 180, height: 180)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: timerInterval), value: scanProgress)

                    Circle()
                        .fill(isPressing ? Color.phoenixGold.opacity(0.2) : Color.white.opacity(0.05))
                        .frame(width: 150, height: 150)
                        .shadow(color: Color.phoenixGold.opacity(isPressing ? 0.4 : 0.0), radius: 15)

                    Image(systemName: isPressing ? "hand.thumbsup.fill" : "hand.thumbsup")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 90, height: 90)
                        .foregroundStyle(isPressing ? .phoenixGold : .phoenixMuted)
                        .scaleEffect(isPressing ? 1.1 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressing)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Circle())
                .onLongPressGesture(minimumDuration: 0.0, pressing: { pressing in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isPressing = pressing
                    }
                    if pressing {
                        handlePressStarted()
                    } else {
                        handlePressEnded()
                    }
                }, perform: {})
            }
            .padding(.horizontal, 30)
        }
        .onDisappear {
            timer?.invalidate()
        }
    }

    private func handlePressStarted() {
        guard !hasCompleted else { return }

        feedbackMessage = "Scanning…"
        feedbackColor = .white

        let totalSteps = scanDuration / timerInterval
        let progressStep = 1.0 / totalSteps

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: timerInterval, repeats: true) { _ in
            if scanProgress < 1.0 {
                scanProgress += progressStep
            } else {
                timer?.invalidate()
                feedbackMessage = "Too late! Release your thumb."
                feedbackColor = .phoenixDestructive
            }
        }
    }

    private func handlePressEnded() {
        timer?.invalidate()

        if feedbackColor == .phoenixDestructive {
            feedbackMessage = "Draining… get ready to try again."
            feedbackColor = .phoenixGold
            startDraining()
            return
        }

        if scanProgress >= 0.95 && scanProgress <= 1.0 {
            feedbackMessage = "Scan successful! Perfect."
            feedbackColor = .phoenixGreen
            scanProgress = 1.0
            hasCompleted = true
            onComplete()
            return
        }

        if scanProgress > 0.01 {
            feedbackMessage = "Scan interrupted. Draining…"
            feedbackColor = .phoenixGold
            startDraining()
        } else {
            resetSensorState()
        }
    }

    private func startDraining() {
        let totalDrainSteps = drainDuration / timerInterval
        let drainStep = 1.0 / totalDrainSteps

        timer = Timer.scheduledTimer(withTimeInterval: timerInterval, repeats: true) { _ in
            if scanProgress > 0.0 {
                scanProgress -= drainStep
            } else {
                timer?.invalidate()
                resetSensorState()
            }
        }
    }

    private func resetSensorState() {
        scanProgress = 0.0
        feedbackMessage = "Hold to scan"
        feedbackColor = .white
    }

    private var feedbackStatusSubtitle: String {
        if isPressing {
            return "Release at just the right moment…"
        } else if feedbackColor == .phoenixGreen {
            return "Great timing!"
        } else if feedbackColor == .phoenixGold {
            return "Press again to stop the drain!"
        } else if feedbackColor == .phoenixDestructive {
            return "You held it too long."
        }
        return "Ready."
    }
}
