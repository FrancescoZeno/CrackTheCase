import SwiftUI
import Combine

/// The `validCardSwipe` turn-order minigame: swipe right on valid access
/// keys and left on expired ones, working through a 10-card deck. A wrong
/// swipe regenerates the deck without pausing the clock. Calls
/// `onComplete` once the whole deck is cleared correctly.
struct TurnValidCardSwipeView: View {
    let onComplete: () -> Void

    @StateObject private var engine = SwipeEngine()

    var body: some View {
        ZStack {
            Color(red: engine.flashError ? 0.4 : 15 / 255, green: engine.flashError ? 0.05 : 23 / 255, blue: engine.flashError ? 0.06 : 42 / 255)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.2), value: engine.flashError)

            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("KEY SCAN")
                            .font(.system(size: 20, weight: .black, design: .monospaced))
                            .foregroundStyle(.phoenixGold)
                        MinigameInstructionText(text: "Swipe right on VALID keys, left on EXPIRED ones — 10 in a row.")
                    }
                    Spacer()

                    Text(engine.phase != .starting ? String(format: "%.2f s", engine.elapsedSeconds) : "--.-- s")
                        .font(.system(size: 32, weight: .black, design: .monospaced))
                        .foregroundStyle(engine.phase == .finished ? .phoenixGold : .white)
                        .glowEffect(color: engine.phase == .finished ? .phoenixGold : .clear, radius: 10)
                }
                .padding(.horizontal, 40)
                .padding(.top, 20)
                .opacity(engine.phase != .starting ? 1.0 : 0.0)

                Spacer()

                ZStack {
                    ForEach(Array(engine.keysStack.enumerated()), id: \.element.id) { index, key in
                        let isTopCard = index == engine.keysStack.count - 1

                        ValidCardSwipeFace(keyData: key)
                            .drawingGroup()
                            .scaleEffect(isTopCard ? 1.0 : 0.9 - CGFloat(engine.keysStack.count - 1 - index) * 0.03)
                            .offset(y: isTopCard ? 0 : CGFloat(engine.keysStack.count - 1 - index) * 10)
                            .offset(isTopCard ? engine.topCardOffset : .zero)
                            .rotationEffect(isTopCard ? .degrees(Double(engine.topCardOffset.width / 15)) : .zero)
                            .zIndex(Double(index))
                            .gesture(
                                isTopCard && engine.phase == .playing ?
                                DragGesture()
                                    .onChanged { gesture in
                                        engine.topCardOffset = gesture.translation
                                    }
                                    .onEnded { gesture in
                                        let swipeThreshold: CGFloat = 80

                                        if gesture.translation.width > swipeThreshold {
                                            engine.handleSwipe(isRightSwipe: true)
                                        } else if gesture.translation.width < -swipeThreshold {
                                            engine.handleSwipe(isRightSwipe: false)
                                        } else {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                                engine.topCardOffset = .zero
                                            }
                                        }
                                    }
                                : nil
                            )
                    }
                }
                .blur(radius: engine.phase == .starting ? 15 : 0)

                Spacer()
            }

            if engine.phase == .starting {
                ZStack {
                    Color.black.opacity(0.6).ignoresSafeArea()
                    VStack(spacing: 16) {
                        Text("SYSTEM PREP")
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .foregroundStyle(.phoenixGold)
                        MinigameInstructionText(text: "Swipe right on VALID keys, left on EXPIRED ones — 10 in a row.")
                            .padding(.horizontal, 40)
                        Text("\(engine.startupCountdown)")
                            .font(.system(size: 130, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .glowEffect(color: .phoenixGold, radius: 20)
                    }
                }
            }

            if engine.phase == .finished {
                ZStack {
                    Color.black.opacity(0.85).ignoresSafeArea()
                    VStack(spacing: 20) {
                        Image(systemName: "lock.open.fill")
                            .font(.system(size: 70))
                            .foregroundStyle(.phoenixGold)
                        Text("ACCESS GRANTED")
                            .font(.system(size: 34, weight: .black, design: .monospaced))
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
        .onAppear {
            engine.startSetup()
            engine.onWin = onComplete
        }
        .onDisappear {
            engine.stop()
        }
    }
}

private struct DigitalKey: Identifiable, Equatable {
    let id = UUID()
    let isExpired: Bool
    let serialCode: String
}

/// Physics/turn engine for the valid/expired card deck: generates a fresh
/// 10-card deck (7 expired, 3 valid), advances the countdown, and resolves
/// each swipe.
private final class SwipeEngine: ObservableObject {
    enum GamePhase {
        case starting
        case playing
        case finished
    }

    @Published var phase: GamePhase = .starting
    @Published var startupCountdown: Int = 5
    @Published var elapsedSeconds: Double = 0.0
    @Published var keysStack: [DigitalKey] = []
    @Published var topCardOffset: CGSize = .zero
    @Published var flashError: Bool = false

    /// Called once when the whole deck has been cleared correctly.
    var onWin: (() -> Void)?

    private var countdownTimer: Timer?
    private var gameTimer: Timer?
    private var gameStartTime: Date?

    func startSetup() {
        generateKeys()

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }

            if self.startupCountdown > 1 {
                self.startupCountdown -= 1
                Haptics.impact(.light)
            } else {
                self.countdownTimer?.invalidate()
                self.startGame()
            }
        }
    }

    private func generateKeys() {
        var newKeys: [DigitalKey] = []

        for _ in 0..<7 {
            newKeys.append(DigitalKey(isExpired: true, serialCode: "ERR-\(Int.random(in: 1000...9999))"))
        }
        for _ in 0..<3 {
            newKeys.append(DigitalKey(isExpired: false, serialCode: "AUTH-\(Int.random(in: 1000...9999))"))
        }

        keysStack = newKeys.shuffled()
    }

    private func startGame() {
        phase = .playing
        gameStartTime = Date()
        Haptics.notify(.success)

        gameTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self, let start = self.gameStartTime else { return }
            self.elapsedSeconds = Date().timeIntervalSince(start)
        }
    }

    /// Stops both timers. Must be called when the owning view disappears
    /// before the deck is cleared — otherwise the 60Hz `gameTimer` keeps
    /// firing indefinitely, since it's only ever invalidated on the win path.
    func stop() {
        countdownTimer?.invalidate()
        gameTimer?.invalidate()
    }

    func handleSwipe(isRightSwipe: Bool) {
        guard let currentKey = keysStack.last, phase == .playing else { return }

        let isValidKey = !currentKey.isExpired

        if (isRightSwipe && isValidKey) || (!isRightSwipe && !isValidKey) {
            Haptics.impact(.rigid)

            withAnimation(.easeOut(duration: 0.25)) {
                topCardOffset = CGSize(width: isRightSwipe ? 800 : -800, height: 0)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self else { return }

                if !self.keysStack.isEmpty {
                    self.keysStack.removeLast()
                }
                self.topCardOffset = .zero

                if self.keysStack.isEmpty {
                    self.phase = .finished
                    self.gameTimer?.invalidate()
                    Haptics.notify(.success)
                    self.onWin?()
                }
            }
        } else {
            Haptics.notify(.error)

            withAnimation(.easeInOut(duration: 0.1)) {
                self.flashError = true
                self.topCardOffset = CGSize(width: isRightSwipe ? 100 : -100, height: 0)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self else { return }
                self.generateKeys()
                self.topCardOffset = .zero

                withAnimation(.easeInOut(duration: 0.2)) {
                    self.flashError = false
                }
            }
        }
    }
}

private struct ValidCardSwipeFace: View {
    let keyData: DigitalKey

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .fill(Color.phoenixCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 25, style: .continuous)
                        .stroke(keyData.isExpired ? Color.phoenixDestructive.opacity(0.4) : Color.phoenixGreen.opacity(0.4), lineWidth: 2)
                )

            VStack(spacing: 20) {
                Text(keyData.isExpired ? "EXPIRED" : "VALID")
                    .font(.system(size: 34, weight: .black, design: .monospaced))
                    .foregroundStyle(keyData.isExpired ? .phoenixDestructive : .phoenixGreen)
                    .glowEffect(color: keyData.isExpired ? .phoenixDestructive : .phoenixGreen, radius: 5)

                Image(systemName: "cpu")
                    .font(.system(size: 50))
                    .foregroundStyle(.phoenixGold.opacity(0.8))

                Text(keyData.serialCode)
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 340, height: 220)
    }
}
