import SwiftUI

/// The `crimeMemoryMatch` turn-order minigame: match 4 pairs of crime-scene
/// icons as fast as possible. A wrong pair flips every card back face-down
/// without pausing the clock. Calls `onComplete` once all 4 pairs are
/// matched.
struct TurnCrimeMemoryMatchView: View {
    let onComplete: () -> Void

    private enum TaskState {
        case countdown
        case playing
    }

    fileprivate struct MemoryCard: Identifiable {
        let id = UUID()
        let symbolName: String
        var isFaceUp: Bool = false
        var isMatched: Bool = false
    }

    @State private var taskState: TaskState = .countdown
    @State private var cards: [MemoryCard] = []
    @State private var selectedIndices: [Int] = []
    @State private var canInteract: Bool = true
    @State private var wrongSelection: Bool = false

    @State private var countdownValue: Int = 5
    @State private var countdownTimer: Timer?
    @State private var startTime: Date?
    @State private var elapsedTime: Double = 0.0
    @State private var gameTimer: Timer?

    private let baseSymbols = [
        "magnifyingglass",
        "laptopcomputer",
        "flask.fill",
        "drop.fill",
    ]

    var body: some View {
        ZStack {
            Color.phoenixBackground.ignoresSafeArea()

            switch taskState {
            case .countdown:
                VStack(spacing: 25) {
                    VStack(spacing: 8) {
                        Text("CRIME SCENE TASK")
                            .font(.system(size: 26, weight: .black, design: .rounded))
                            .foregroundStyle(.phoenixGold)

                        MinigameInstructionText(text: "Tap 2 cards to match all 4 pairs. A wrong pair flips back over, but the clock keeps running!")
                            .padding(.horizontal, 40)
                    }

                    Text("\(countdownValue)")
                        .font(.system(size: 90, weight: .black, design: .monospaced))
                        .foregroundStyle(.phoenixGold)
                        .id(countdownValue)
                }

            case .playing:
                VStack(spacing: 15) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("EVIDENCE CORRELATION")
                                .font(.system(size: 24, weight: .black, design: .rounded))
                                .foregroundStyle(.phoenixGold)
                            Text("Find the matching evidence. Speed determines your turn order.")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.5))
                        }

                        Spacer()

                        HStack(spacing: 8) {
                            Image(systemName: "stopwatch")
                                .foregroundStyle(.phoenixGold)
                            Text(String(format: "%.2fs", elapsedTime))
                                .font(.system(size: 20, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 15)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.07))
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.phoenixGold.opacity(0.3), lineWidth: 1))
                    }
                    .padding(.horizontal, 40)

                    Spacer()

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: 4), spacing: 20) {
                        ForEach(0..<cards.count, id: \.self) { index in
                            MemoryCardFace(
                                card: cards[index],
                                isWrong: wrongSelection && selectedIndices.contains(index)
                            )
                            .aspectRatio(1.2, contentMode: .fit)
                            .onTapGesture {
                                handleCardSelection(at: index)
                            }
                        }
                    }
                    .padding(.horizontal, 60)
                    .frame(maxWidth: 700)

                    Spacer()
                }
                .padding(.vertical, 20)
            }
        }
        .onAppear {
            startCountdownPhase()
        }
        .onDisappear {
            stopGameTimer()
            countdownTimer?.invalidate()
        }
    }

    private func startCountdownPhase() {
        let doubledSymbols = baseSymbols + baseSymbols
        let shuffled = doubledSymbols.shuffled()
        cards = shuffled.map { MemoryCard(symbolName: $0) }

        selectedIndices.removeAll()
        wrongSelection = false
        canInteract = true
        elapsedTime = 0.0

        countdownValue = 5
        taskState = .countdown

        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if countdownValue > 1 {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                    countdownValue -= 1
                }
            } else {
                countdownTimer?.invalidate()
                countdownTimer = nil

                taskState = .playing
                startTime = Date()
                startGameTimer()
            }
        }
    }

    private func resumeClockAfterFailure() {
        selectedIndices.removeAll()
        wrongSelection = false
        canInteract = true
        startGameTimer()
    }

    private func handleCardSelection(at index: Int) {
        guard canInteract, !cards[index].isFaceUp, !cards[index].isMatched else { return }

        withAnimation(.easeInOut(duration: 0.2)) {
            cards[index].isFaceUp = true
        }
        selectedIndices.append(index)

        if selectedIndices.count == 2 {
            canInteract = false
            let first = selectedIndices[0]
            let second = selectedIndices[1]

            if cards[first].symbolName == cards[second].symbolName {
                cards[first].isMatched = true
                cards[second].isMatched = true
                selectedIndices.removeAll()
                canInteract = true

                if cards.allSatisfy(\.isMatched) {
                    stopGameTimer()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        onComplete()
                    }
                }
            } else {
                withAnimation(.default) {
                    wrongSelection = true
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        for i in 0..<cards.count {
                            cards[i].isFaceUp = false
                            cards[i].isMatched = false
                        }
                    }
                    resumeClockAfterFailure()
                }
            }
        }
    }

    private func startGameTimer() {
        gameTimer?.invalidate()
        gameTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            if let start = startTime {
                elapsedTime = Date().timeIntervalSince(start)
            }
        }
    }

    private func stopGameTimer() {
        gameTimer?.invalidate()
        gameTimer = nil
    }
}

private struct MemoryCardFace: View {
    fileprivate let card: TurnCrimeMemoryMatchView.MemoryCard
    let isWrong: Bool

    var body: some View {
        ZStack {
            if card.isFaceUp || card.isMatched {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isWrong ? Color.phoenixDestructive : (card.isMatched ? Color.phoenixGreen.opacity(0.8) : Color.phoenixGold), lineWidth: 2)
                    )

                Image(systemName: card.symbolName)
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(isWrong ? Color.phoenixDestructive : (card.isMatched ? Color.phoenixGreen : .white))
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.phoenixGold.opacity(0.3), lineWidth: 1.5)
                    )
                    .overlay(
                        Image(systemName: "scope")
                            .font(.system(size: 22))
                            .foregroundStyle(.phoenixGold.opacity(0.25))
                    )
            }
        }
        .rotation3DEffect(.degrees(card.isFaceUp ? 180 : 0), axis: (x: 0.0, y: 1.0, z: 0.0))
    }
}
