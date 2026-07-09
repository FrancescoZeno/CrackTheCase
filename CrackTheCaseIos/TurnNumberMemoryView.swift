import SwiftUI

/// The `numberMemory` turn-order minigame: memorize a 5-digit sequence
/// shown briefly, then re-enter it on a numeric keypad. Calls `onComplete`
/// once the player enters the sequence correctly.
struct TurnNumberMemoryView: View {
    let onComplete: () -> Void

    @State private var targetSequence: [Int] = []
    @State private var userSequence: [Int] = []
    @State private var isShowingSequence = false
    @State private var isGameActive = false
    @State private var hasWon = false
    @State private var feedbackMessage = "Press to START"
    @State private var feedbackColor: Color = .white

    private let sequenceLength = 5
    private let displayDuration: TimeInterval = 3

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 20) {
                VStack(spacing: 10) {
                    Text("Memory Numbers")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(.phoenixGold)

                    MinigameInstructionText(text: "Memorize the 5 numbers, then type them back in the same order.")

                    Spacer(minLength: 4)

                    VStack {
                        if isShowingSequence {
                            HStack(spacing: 8) {
                                ForEach(targetSequence, id: \.self) { num in
                                    Text("\(num)")
                                        .font(.system(size: 26, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                        .frame(width: 34, height: 44)
                                        .background(Color.phoenixGold.opacity(0.2))
                                        .cornerRadius(8)
                                }
                            }
                            .transition(.opacity)
                        } else if isGameActive {
                            VStack(spacing: 4) {
                                Text("Enter the sequence:")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.phoenixMuted)

                                HStack(spacing: 8) {
                                    ForEach(0..<sequenceLength, id: \.self) { index in
                                        Text(index < userSequence.count ? "\(userSequence[index])" : "_")
                                            .font(.system(size: 26, weight: .bold, design: .rounded))
                                            .foregroundStyle(.white)
                                            .frame(width: 34, height: 44)
                                            .background(Color.white.opacity(0.08))
                                            .cornerRadius(8)
                                    }
                                }
                            }
                        } else {
                            Text(feedbackMessage)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(feedbackColor)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                    }
                    .frame(height: 64)

                    Spacer(minLength: 4)

                    if !isGameActive && !hasWon {
                        Button(action: startGame) {
                            Text(feedbackMessage == "Press to START" ? "START" : "Try Again")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.phoenixGreen)
                                .cornerRadius(12)
                        }
                    }
                }
                .frame(width: geometry.size.width * 0.45)

                Divider()

                VStack {
                    Spacer()
                    NumberMemoryKeyboard(userSequence: $userSequence, isEnabled: isGameActive && !isShowingSequence) {
                        checkResult()
                    }
                    Spacer()
                }
                .frame(width: geometry.size.width * 0.5)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color.phoenixBackground)
    }

    private func startGame() {
        userSequence.removeAll()
        feedbackMessage = ""
        isGameActive = true
        hasWon = false

        targetSequence = (0..<sequenceLength).map { _ in Int.random(in: 0...9) }

        withAnimation {
            isShowingSequence = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + displayDuration) {
            withAnimation {
                isShowingSequence = false
            }
        }
    }

    private func checkResult() {
        isGameActive = false
        if userSequence == targetSequence {
            feedbackMessage = "Correct!"
            feedbackColor = .phoenixGreen
            hasWon = true
            onComplete()
        } else {
            let correctString = targetSequence.map { String($0) }.joined(separator: " ")
            feedbackMessage = "Wrong! The correct sequence was: \(correctString)"
            feedbackColor = .phoenixDestructive
            hasWon = false
        }
    }
}

private struct NumberMemoryKeyboard: View {
    @Binding var userSequence: [Int]
    var isEnabled: Bool
    var onComplete: () -> Void

    let buttons = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["Clear", "0", "⌫"],
    ]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(buttons, id: \.self) { row in
                HStack(spacing: 12) {
                    ForEach(row, id: \.self) { label in
                        Button {
                            buttonPressed(label)
                        } label: {
                            Text(label)
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(textColor(for: label))
                                .frame(maxWidth: .infinity, minHeight: 40, maxHeight: 45)
                                .background(buttonColor(for: label))
                                .cornerRadius(10)
                        }
                        .disabled(!isEnabled || (isActionKey(label) && userSequence.isEmpty && label != "Clear"))
                    }
                }
            }
        }
        .opacity(isEnabled ? 1.0 : 0.5)
        .animation(.default, value: isEnabled)
    }

    private func buttonPressed(_ label: String) {
        if label == "⌫" {
            if !userSequence.isEmpty { userSequence.removeLast() }
        } else if label == "Clear" {
            userSequence.removeAll()
        } else if userSequence.count < 5, let num = Int(label) {
            userSequence.append(num)
            if userSequence.count == 5 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    onComplete()
                }
            }
        }
    }

    private func isActionKey(_ label: String) -> Bool {
        label == "Clear" || label == "⌫"
    }

    private func buttonColor(for label: String) -> Color {
        isActionKey(label) ? Color.white.opacity(0.15) : Color.phoenixCard
    }

    private func textColor(for label: String) -> Color {
        label == "Clear" ? .phoenixDestructive : .white
    }
}

// Landscape preview — this minigame (and every other one) is only ever
// shown in landscape on a real phone; forcing that orientation here is
// what actually catches "content overflows the bottom on a small iPhone"
// bugs like the START button being cut off, straight in Xcode's Canvas,
// without launching the simulator or playing through a real game to reach
// this screen. Reuses the same "just pass a no-op closure" pattern as
// `MinigameDebugMenu.swift`'s `MinigameDebugPlayView` — no live host needed.
#Preview("Number Memory — iPhone landscape", traits: .landscapeRight) {
    TurnNumberMemoryView(onComplete: {})
        .preferredColorScheme(.dark)
}
