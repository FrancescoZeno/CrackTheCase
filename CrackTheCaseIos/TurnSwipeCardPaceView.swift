import SwiftUI

/// The `swipeCardPace` turn-order minigame: drag a card along a track at a
/// steady pace — too fast, too slow, or reversing direction all fail.
/// Calls `onComplete` once swiped at the right speed.
struct TurnSwipeCardPaceView: View {
    let onComplete: () -> Void

    fileprivate enum GameState {
        case idle, dragging, success, failed
    }

    @State private var state: GameState = .idle
    @State private var cardOffset: CGFloat = 0
    @State private var feedbackMessage = "PLEASE SWIPE CARD"
    @State private var feedbackColor: Color = .white

    @State private var swipeStartTime: Date?
    @State private var lastDragX: CGFloat = 0

    private let minSwipeTime: TimeInterval = 0.45
    private let maxSwipeTime: TimeInterval = 0.65
    private let cardWidth: CGFloat = 120.0

    var body: some View {
        ZStack {
            Color.phoenixBackground.ignoresSafeArea()

            HStack(spacing: 30) {
                VStack(spacing: 25) {
                    Text("SECURE ID SCANNER")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(.phoenixGold)
                        .multilineTextAlignment(.center)

                    VStack(spacing: 12) {
                        Text(feedbackMessage)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(feedbackColor)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(feedbackColor.opacity(0.5), lineWidth: 2)
                            )

                        MinigameInstructionText(text: "Drag the card all the way across at a steady pace — not too fast, not too slow, and never backwards.")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.leading, 20)

                Divider()
                    .background(Color.white.opacity(0.15))
                    .padding(.vertical, 40)

                GeometryReader { geometry in
                    let trackWidth = geometry.size.width
                    let maxOffset = trackWidth - cardWidth

                    VStack {
                        Spacer()

                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 15)
                                .fill(Color.white.opacity(0.08))
                                .frame(height: 70)
                                .overlay(
                                    HStack {
                                        Text("» » » » »")
                                            .font(.system(size: 22, weight: .black, design: .rounded))
                                            .foregroundStyle(.white.opacity(0.3))
                                            .padding(.leading, cardWidth + 10)
                                        Spacer()
                                        Circle()
                                            .fill(ledColor)
                                            .frame(width: 15, height: 15)
                                            .padding(.trailing, 20)
                                    }
                                )

                            SwipeCardFace(state: state)
                                .frame(width: cardWidth, height: 160)
                                .offset(x: cardOffset)
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            handleDrag(value: value, maxOffset: maxOffset)
                                        }
                                        .onEnded { _ in
                                            handleDragEnd(maxOffset: maxOffset)
                                        }
                                )
                                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: state == .failed || state == .idle)
                        }

                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.trailing, 20)
            }
            .padding(.horizontal, 20)
        }
    }

    private var ledColor: Color {
        switch state {
        case .idle: return .white.opacity(0.4)
        case .dragging: return .phoenixGold
        case .success: return .phoenixGreen
        case .failed: return .phoenixDestructive
        }
    }

    private func handleDrag(value: DragGesture.Value, maxOffset: CGFloat) {
        guard state != .success && state != .failed else { return }

        let currentX = value.translation.width

        if swipeStartTime == nil && currentX > 0 {
            swipeStartTime = Date()
            state = .dragging
            feedbackMessage = "READING…"
            feedbackColor = .phoenixGold
            lastDragX = currentX
        }

        if currentX < lastDragX - 3.0 {
            triggerFail(reason: "UNEVEN MOTION DETECTED.")
            return
        }

        lastDragX = currentX
        cardOffset = max(0, min(currentX, maxOffset))
    }

    private func handleDragEnd(maxOffset: CGFloat) {
        guard state != .success && state != .failed else { return }

        guard let start = swipeStartTime else {
            resetCard()
            return
        }

        let swipeDuration = Date().timeIntervalSince(start)

        if cardOffset < maxOffset - 5 {
            triggerFail(reason: "INCOMPLETE SWIPE.")
            return
        }

        if swipeDuration < minSwipeTime {
            triggerFail(reason: "TOO FAST. TRY AGAIN.")
            return
        }

        if swipeDuration > maxSwipeTime {
            triggerFail(reason: "TOO SLOW. TRY AGAIN.")
            return
        }

        state = .success
        feedbackMessage = "ACCEPTED. ACCESS GRANTED."
        feedbackColor = .phoenixGreen
        Haptics.notify(.success)
        onComplete()
    }

    private func triggerFail(reason: String) {
        state = .failed
        feedbackMessage = reason
        feedbackColor = .phoenixDestructive
        Haptics.notify(.error)
        cardOffset = 0

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if self.state == .failed {
                self.resetCard()
            }
        }
    }

    private func resetCard() {
        state = .idle
        cardOffset = 0
        lastDragX = 0
        feedbackMessage = "PLEASE SWIPE CARD"
        feedbackColor = .white
        swipeStartTime = nil
    }
}

private struct SwipeCardFace: View {
    var state: TurnSwipeCardPaceView.GameState

    fileprivate init(state: TurnSwipeCardPaceView.GameState) {
        self.state = state
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 5)

            VStack {
                Rectangle()
                    .fill(Color.black)
                    .frame(height: 30)
                    .padding(.top, 15)

                Spacer()

                HStack(spacing: 12) {
                    Circle()
                        .fill(Color.caseBlue.opacity(0.2))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "person.fill")
                                .foregroundColor(.caseBlue.opacity(0.5))
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 40, height: 6)
                        Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 30, height: 6)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 15)
            }

            if state == .failed {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.phoenixDestructive.opacity(0.3))
            }
        }
    }
}
