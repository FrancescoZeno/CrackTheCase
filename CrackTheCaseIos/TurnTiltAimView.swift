import SwiftUI
import CoreMotion
import Combine

/// The `tiltAim` turn-order minigame: tilt the phone (no touching the
/// screen) to keep a reticle over a drifting target for 4 seconds straight.
/// Calls `onComplete` once held for long enough.
struct TurnTiltAimView: View {
    let onComplete: () -> Void

    @StateObject private var engine = TiltAimEngine()

    var body: some View {
        ZStack {
            Color.phoenixBackground.ignoresSafeArea()

            VStack(spacing: 20) {
                HStack {
                    Text(engine.state == .completed ? "ALIGNMENT COMPLETE" : "Keep the reticle centered")
                        .font(.system(size: 20, weight: .black, design: .monospaced))
                        .foregroundStyle(engine.state == .completed ? .phoenixGreen : .cyan)
                        .glowEffect(color: engine.state == .completed ? .phoenixGreen : .cyan, radius: engine.state == .completed ? 15 : 8)

                    Spacer()

                    Text(engine.formattedTime())
                        .font(.system(size: 24, weight: .black, design: .monospaced))
                        .foregroundStyle(engine.state == .completed ? .phoenixGreen : .white)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(8)
                }
                .padding(.horizontal, 40)
                .padding(.top, 10)

                ZStack {
                    if engine.state != .countdown {
                        Circle()
                            .stroke(Color.phoenixDestructive.opacity(0.6), lineWidth: 4)
                            .frame(width: 80, height: 80)
                            .overlay(Circle().fill(Color.phoenixDestructive.opacity(0.15)))
                            .offset(x: engine.targetX, y: engine.targetY)

                        TiltAimReticle(isAligned: engine.isAligned)
                            .offset(x: engine.playerX, y: engine.playerY)

                        Circle()
                            .trim(from: 0.0, to: CGFloat(engine.progress / 4.0))
                            .stroke(engine.isAligned ? Color.phoenixGreen : Color.clear, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .frame(width: 100, height: 100)
                            .rotationEffect(.degrees(-90))
                            .offset(x: engine.targetX, y: engine.targetY)
                    }

                    if engine.state == .countdown {
                        Text("\(engine.countdownNumber)")
                            .font(.system(size: 150, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .shadow(color: .cyan.opacity(0.8), radius: 20)
                            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: engine.countdownNumber)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            engine.startSetup()
            engine.onWin = onComplete
        }
        .onDisappear {
            engine.stopGame()
        }
    }
}

private struct TiltAimReticle: View {
    var isAligned: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(isAligned ? Color.phoenixGreen : Color.cyan, lineWidth: 2)
                .frame(width: 30, height: 30)
                .glowEffect(color: isAligned ? .phoenixGreen : .cyan, radius: isAligned ? 10 : 5)

            Rectangle().frame(width: 2, height: 12).offset(y: -22)
            Rectangle().frame(width: 2, height: 12).offset(y: 22)
            Rectangle().frame(width: 12, height: 2).offset(x: -22)
            Rectangle().frame(width: 12, height: 2).offset(x: 22)

            Circle().frame(width: 4, height: 4)
        }
        .foregroundStyle(isAligned ? Color.phoenixGreen : Color.cyan)
    }
}

/// Physics engine for the tilt-aim reticle: pre-warms `CMDeviceMotion`
/// updates on appear to avoid sensor lag, drives an inertial reticle from
/// device tilt, and drifts a target toward randomly-chosen destinations.
private final class TiltAimEngine: ObservableObject {
    enum GameState {
        case countdown
        case playing
        case completed
    }

    @Published var state: GameState = .countdown
    @Published var countdownNumber: Int = 5
    @Published var elapsedTime: Double = 0.0

    private var motionManager = CMMotionManager()
    private let motionQueue = OperationQueue()

    private var countdownTimer: Timer?
    private var gameLoopTimer: Timer?
    private var targetTimer: Timer?
    private var startTime: Date?

    @Published var playerX: CGFloat = 0.0
    @Published var playerY: CGFloat = 0.0

    @Published var targetX: CGFloat = 0.0
    @Published var targetY: CGFloat = 0.0
    private var destinationX: CGFloat = 0.0
    private var destinationY: CGFloat = 0.0

    @Published var progress: Double = 0.0
    @Published var isAligned = false

    private var velocityX: CGFloat = 0.0
    private var velocityY: CGFloat = 0.0

    /// Called once when `progress` reaches the 4-second target.
    var onWin: (() -> Void)?

    func startSetup() {
        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
            motionManager.startDeviceMotionUpdates(to: motionQueue) { [weak self] data, _ in
                guard let self, let data else { return }
                DispatchQueue.main.async {
                    if self.state == .playing {
                        self.processMotion(data: data)
                    }
                }
            }
        }

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }

            if self.countdownNumber > 1 {
                self.countdownNumber -= 1
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } else {
                self.countdownTimer?.invalidate()
                self.state = .playing
                self.startTime = Date()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                self.startGameLogic()
            }
        }
    }

    private func startGameLogic() {
        pickNewDestination()
        targetX = destinationX
        targetY = destinationY

        gameLoopTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.updatePhysicsAndLogic()
        }

        targetTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: true) { [weak self] _ in
            self?.pickNewDestination()
        }
    }

    private func processMotion(data: CMDeviceMotion) {
        let rawTiltX = CGFloat(data.gravity.y)
        let rawTiltY = CGFloat(data.gravity.x)

        let deadZone: CGFloat = 0.02
        let tiltX = abs(rawTiltX) > deadZone ? rawTiltX : 0
        let tiltY = abs(rawTiltY) > deadZone ? rawTiltY : 0

        velocityX += tiltX * 1.6
        velocityY += tiltY * 1.6

        velocityX *= 0.85
        velocityY *= 0.85

        playerX += velocityX
        playerY += velocityY

        let limitX: CGFloat = 380
        let limitY: CGFloat = 170

        if playerX > limitX { playerX = limitX; velocityX = 0 }
        if playerX < -limitX { playerX = -limitX; velocityX = 0 }
        if playerY > limitY { playerY = limitY; velocityY = 0 }
        if playerY < -limitY { playerY = -limitY; velocityY = 0 }
    }

    private func pickNewDestination() {
        destinationX = CGFloat.random(in: -280...280)
        destinationY = CGFloat.random(in: -120...120)
    }

    private func updatePhysicsAndLogic() {
        guard state == .playing else { return }

        if let start = startTime {
            elapsedTime = Date().timeIntervalSince(start)
        }

        targetX += (destinationX - targetX) * 0.006
        targetY += (destinationY - targetY) * 0.006

        let dx = playerX - targetX
        let dy = playerY - targetY
        let distance = sqrt(dx * dx + dy * dy)

        if distance < 40 {
            isAligned = true
            progress += (1.0 / 60.0)

            if Int(progress * 60) % 15 == 0 {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            }

            if progress >= 4.0 {
                state = .completed
                stopGame()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onWin?()
            }
        } else {
            isAligned = false
            if progress > 0 {
                progress -= (1.0 / 40.0)
                if progress < 0 { progress = 0 }
            }
        }
    }

    func stopGame() {
        motionManager.stopDeviceMotionUpdates()
        gameLoopTimer?.invalidate()
        targetTimer?.invalidate()
        countdownTimer?.invalidate()
    }

    func formattedTime() -> String {
        String(format: "%05.2fs", elapsedTime)
    }
}
