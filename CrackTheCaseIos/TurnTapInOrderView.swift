import SwiftUI
import Combine

/// The `tapInOrder` turn-order minigame: tap 9 shuffled numbers in
/// ascending order before a 7-second timer runs out. Calls `onComplete`
/// once all 9 are tapped in order.
struct TurnTapInOrderView: View {
    let onComplete: () -> Void

    @State private var numbers = (1...9).shuffled()
    @State private var currentTarget = 1
    @State private var isCompleted = false
    @State private var isFailed = false

    @State private var timeRemaining: Double = 7.0
    private let totalTime: Double = 7.0
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    private let positions: [CGPoint] = [
        CGPoint(x: 0.15, y: 0.25), CGPoint(x: 0.50, y: 0.20), CGPoint(x: 0.85, y: 0.25),
        CGPoint(x: 0.30, y: 0.50), CGPoint(x: 0.70, y: 0.55), CGPoint(x: 0.10, y: 0.70),
        CGPoint(x: 0.55, y: 0.85), CGPoint(x: 0.90, y: 0.80), CGPoint(x: 0.40, y: 0.65),
    ]

    var body: some View {
        ZStack {
            Color.phoenixBackground.ignoresSafeArea()

            VStack(spacing: 15) {
                HStack(spacing: 20) {
                    Text(isCompleted ? "SEQUENCE CORRECT" : (isFailed ? "SYSTEM LOCKED" : "Tap: \(currentTarget)"))
                        .font(.system(size: 24, weight: .black, design: .monospaced))
                        .foregroundStyle(isCompleted ? .phoenixGreen : (isFailed ? .phoenixDestructive : .phoenixGold))
                        .id(isFailed)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.08))
                                .frame(height: 8)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(isFailed ? Color.phoenixDestructive : (timeRemaining < 2.0 ? .phoenixDestructive : .phoenixGold))
                                .frame(width: geo.size.width * CGFloat(timeRemaining / totalTime), height: 8)
                                .animation(.linear(duration: 0.1), value: timeRemaining)
                        }
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    }
                    .frame(height: 20)
                }
                .padding(.horizontal, 40)
                .padding(.top, 10)

                GeometryReader { geometry in
                    ZStack {
                        RoundedRectangle(cornerRadius: 25, style: .continuous)
                            .fill(Color.phoenixCard)
                            .overlay(
                                RoundedRectangle(cornerRadius: 25, style: .continuous)
                                    .stroke(isFailed ? Color.phoenixDestructive.opacity(0.3) : Color.white.opacity(0.05), lineWidth: 1)
                            )

                        ForEach(0..<9, id: \.self) { index in
                            let number = numbers[index]

                            TapInOrderButton(
                                number: number,
                                isTarget: number == currentTarget,
                                isAlreadyPressed: number < currentTarget,
                                isDisabled: isFailed || isCompleted
                            ) {
                                handleTap(on: number)
                            }
                            .position(
                                x: positions[index].x * geometry.size.width,
                                y: positions[index].y * geometry.size.height
                            )
                        }

                        if isFailed {
                            Color.black.opacity(0.85)
                                .cornerRadius(25)
                                .overlay(
                                    VStack(spacing: 20) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.system(size: 60))
                                            .foregroundStyle(.phoenixDestructive)

                                        Text("TIME'S UP")
                                            .font(.system(size: 26, weight: .bold, design: .monospaced))
                                            .foregroundStyle(.white)

                                        Button(action: resetGame) {
                                            Text("TRY AGAIN")
                                                .font(.system(size: 20, weight: .black, design: .monospaced))
                                                .foregroundStyle(.phoenixDestructive)
                                                .padding(.horizontal, 30)
                                                .padding(.vertical, 15)
                                                .background(Color.phoenixDestructive.opacity(0.15))
                                                .cornerRadius(10)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 10)
                                                        .stroke(Color.phoenixDestructive, lineWidth: 2)
                                                )
                                        }
                                    }
                                )
                                .transition(.opacity)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .onReceive(timer) { _ in
            guard !isCompleted && !isFailed else { return }

            if timeRemaining > 0 {
                timeRemaining -= 0.1
            } else {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isFailed = true
                    timeRemaining = 0
                }
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    private func handleTap(on number: Int) {
        guard !isCompleted && !isFailed else { return }

        if number == currentTarget {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()

            if currentTarget == 9 {
                withAnimation(.easeInOut(duration: 0.5)) {
                    isCompleted = true
                }
                onComplete()
            } else {
                withAnimation(.spring()) {
                    currentTarget += 1
                }
            }
        } else if number > currentTarget {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            withAnimation(.easeInOut(duration: 0.3)) {
                isFailed = true
            }
        }
    }

    private func resetGame() {
        withAnimation(.easeInOut(duration: 0.3)) {
            numbers = (1...9).shuffled()
            currentTarget = 1
            timeRemaining = totalTime
            isFailed = false
            isCompleted = false
        }
    }
}

private struct TapInOrderButton: View {
    let number: Int
    let isTarget: Bool
    let isAlreadyPressed: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("\(number)")
                .font(.system(size: 38, weight: .heavy, design: .monospaced))
                .foregroundStyle(isAlreadyPressed ? Color.phoenixGold.opacity(0.3) : (isTarget ? .phoenixGold : .white.opacity(0.8)))
                .frame(width: 90, height: 90)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.06))
                )
                .overlay(
                    Circle()
                        .stroke(isAlreadyPressed ? Color.phoenixGold.opacity(0.5) : Color.clear, lineWidth: 3)
                )
        }
        .disabled(isAlreadyPressed || isDisabled)
    }
}
