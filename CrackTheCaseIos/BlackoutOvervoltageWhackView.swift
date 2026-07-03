import SwiftUI

/// The `overvoltageWhack` Black-out task: tap sparks before they fade.
/// Completed independently by each player — calls `onComplete` once
/// `totalSparksRequired` have been cleared in time.
struct BlackoutOvervoltageWhackView: View {
    let onComplete: () -> Void

    private let totalSparksRequired = 10
    private let totalTimeAllowed: Double = 20
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 3)

    @State private var sparksCleared = 0
    @State private var timeRemaining: Double = 20
    @State private var activeSparkIndex: Int?
    @State private var gameTimer: Timer?
    @State private var sparkTimer: Timer?
    @State private var currentSparkDuration: Double = 1.5
    @State private var isGameOver = false
    @State private var isWon = false
    @State private var showWhiteFlash = false

    var body: some View {
        VStack(spacing: 20) {
            Text("SHORT CIRCUIT PANEL")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(.phoenixGold)
                .tracking(1)

            HStack(spacing: 24) {
                VStack(spacing: 4) {
                    Text("SPARKS CLEARED")
                        .font(.caption.bold())
                        .foregroundStyle(.phoenixMuted)
                    Text("\(sparksCleared) / \(totalSparksRequired)")
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundStyle(.phoenixGreen)
                }
                VStack(spacing: 4) {
                    Text("TIME LEFT")
                        .font(.caption.bold())
                        .foregroundStyle(.phoenixMuted)
                    Text(String(format: "%.1fs", timeRemaining))
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundStyle(timeRemaining < 5 ? .phoenixDestructive : .phoenixGold)
                }
            }

            ProgressView(value: Double(sparksCleared), total: Double(totalSparksRequired))
                .tint(.phoenixGreen)
                .padding(.horizontal, 30)

            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(0..<9, id: \.self) { index in
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.phoenixCard)
                            .frame(height: 84)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )

                        if activeSparkIndex == index {
                            Button {
                                handleSparkTap()
                            } label: {
                                Image(systemName: "bolt.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 40, height: 40)
                                    .foregroundStyle(.yellow)
                                    .shadow(color: .yellow, radius: 8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)

            Spacer()
        }
        .padding(.top, 20)
        .overlay {
            if showWhiteFlash {
                Color.white.ignoresSafeArea()
            }
        }
        .overlay {
            if isGameOver {
                ZStack {
                    Color.black.opacity(0.85).ignoresSafeArea()
                    VStack(spacing: 20) {
                        Text(isWon ? "POWER RESTORED!" : "SYSTEM BURNED OUT!")
                            .font(.system(size: 26, weight: .black, design: .rounded))
                            .foregroundStyle(isWon ? .phoenixGreen : .phoenixDestructive)

                        Text(isWon ? "You saved the fuses in time." : "The fuses blew. Try again.")
                            .font(.body)
                            .foregroundStyle(.phoenixMuted)

                        if !isWon {
                            Button {
                                startGame()
                            } label: {
                                Text("RETRY")
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 52)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.phoenixDestructive)
                            .padding(.horizontal, 50)
                        }
                    }
                }
            }
        }
        .onAppear { startGame() }
        .onDisappear { stopTimers() }
    }

    private func startGame() {
        sparksCleared = 0
        timeRemaining = totalTimeAllowed
        currentSparkDuration = 1.5
        isGameOver = false
        isWon = false
        showWhiteFlash = false

        gameTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if timeRemaining > 0 {
                timeRemaining -= 0.1
            } else {
                endGame(won: false)
            }
        }
        spawnSpark()
    }

    private func spawnSpark() {
        sparkTimer?.invalidate()
        var nextIndex = Int.random(in: 0..<9)
        while nextIndex == activeSparkIndex {
            nextIndex = Int.random(in: 0..<9)
        }

        withAnimation(.easeInOut(duration: 0.1)) {
            activeSparkIndex = nextIndex
        }

        sparkTimer = Timer.scheduledTimer(withTimeInterval: currentSparkDuration, repeats: false) { _ in
            spawnSpark()
        }
    }

    private func handleSparkTap() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        sparksCleared += 1
        if sparksCleared >= totalSparksRequired {
            endGame(won: true)
            return
        }
        currentSparkDuration = max(0.4, 1.5 - (Double(sparksCleared) * 0.12))
        spawnSpark()
    }

    private func endGame(won: Bool) {
        stopTimers()
        isWon = won
        activeSparkIndex = nil

        if won {
            withAnimation(.easeInOut(duration: 0.1)) {
                showWhiteFlash = true
            }
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showWhiteFlash = false
                }
                onComplete()
            }
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            withAnimation(.easeInOut) {
                isGameOver = true
            }
        }
    }

    private func stopTimers() {
        gameTimer?.invalidate()
        sparkTimer?.invalidate()
        gameTimer = nil
        sparkTimer = nil
    }
}
