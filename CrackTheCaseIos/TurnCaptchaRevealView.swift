import SwiftUI

/// The `captchaReveal` turn-order minigame: drag an eye icon along a
/// password bar to reveal a hidden captcha letter, then pick it from a
/// grid. Calls `onComplete` once the correct letter is picked.
struct TurnCaptchaRevealView: View {
    let onComplete: () -> Void

    private let possibleLetters = ["A", "B", "C", "D", "E", "F"]

    @State private var secretLetter = "C"
    @State private var letterRotation: Double = 0.0
    @State private var letterYOffset: CGFloat = 0.0

    @State private var dragOffset: CGFloat = 0
    @State private var feedbackMessage = "Drag the eye to reveal the letter"
    @State private var feedbackColor: Color = .phoenixMuted
    @State private var isCompleted = false

    private let barWidth: CGFloat = 260
    private let eyeSize: CGFloat = 40
    private let slotPositions: [CGFloat] = [40, 85, 130, 175, 220]

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 30) {
                VStack(spacing: 20) {
                    Text("CAPTCHA Decryption")
                        .font(.title2)
                        .bold()
                        .foregroundStyle(.white)

                    Text(feedbackMessage)
                        .font(.subheadline)
                        .foregroundStyle(feedbackColor)
                        .multilineTextAlignment(.center)
                        .frame(height: 40)

                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.phoenixCard)
                            .frame(width: barWidth, height: 60)

                        HStack(spacing: 0) {
                            ForEach(0..<5) { index in
                                ZStack {
                                    if index == 2 {
                                        if dragOffset + (eyeSize / 2) > slotPositions[index] {
                                            Text(secretLetter)
                                                .font(.system(size: 32, weight: .black, design: .serif))
                                                .foregroundStyle(.phoenixGold)
                                                .italic()
                                                .rotationEffect(.degrees(letterRotation))
                                                .offset(y: letterYOffset)
                                                .blur(radius: isCompleted ? 0 : 0.3)
                                        } else {
                                            Text("•")
                                                .font(.system(size: 35))
                                                .foregroundStyle(.white)
                                        }
                                    } else {
                                        Text("•")
                                            .font(.system(size: 35))
                                            .foregroundStyle(dragOffset + (eyeSize / 2) > slotPositions[index] ? Color.white.opacity(0.4) : .white)
                                    }
                                }
                                .frame(width: 45)
                            }
                        }
                        .padding(.leading, 15)

                        Image(systemName: "eye")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: eyeSize, height: eyeSize)
                            .background(Color.white)
                            .clipShape(Circle())
                            .offset(x: dragOffset)
                            .disabled(isCompleted)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        let newOffset = value.location.x - (eyeSize / 2)
                                        dragOffset = min(max(0, newOffset), barWidth - eyeSize)
                                    }
                            )
                    }
                    .frame(width: barWidth, height: 60)
                }
                .frame(width: geometry.size.width * 0.55)

                Divider().background(Color.white.opacity(0.15))

                VStack(spacing: 12) {
                    Text("Select")
                        .font(.headline)
                        .foregroundStyle(.phoenixMuted)

                    let columns = [GridItem(.flexible()), GridItem(.flexible())]

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(possibleLetters, id: \.self) { letter in
                            Button {
                                checkAnswer(letter)
                            } label: {
                                Text(letter)
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity, minHeight: 45)
                                    .background(Color.white.opacity(0.08))
                                    .cornerRadius(10)
                            }
                            .disabled(isCompleted)
                        }
                    }
                }
                .frame(width: geometry.size.width * 0.35)
            }
            .padding()
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(Color.phoenixBackground)
            .onAppear {
                generateNewCaptcha()
            }
        }
    }

    private func checkAnswer(_ letter: String) {
        if letter == secretLetter {
            feedbackMessage = "Access granted! Captcha verified."
            feedbackColor = .phoenixGreen
            isCompleted = true
            onComplete()
        } else {
            feedbackMessage = "Verification failed! Try reading the distorted letter again."
            feedbackColor = .phoenixDestructive
        }
    }

    private func generateNewCaptcha() {
        if let randomLetter = possibleLetters.randomElement() {
            secretLetter = randomLetter
        }

        letterRotation = Double.random(in: -25...25)
        letterYOffset = CGFloat.random(in: -6...6)

        dragOffset = 0
        isCompleted = false
        feedbackMessage = "Drag the eye to reveal the letter"
        feedbackColor = .phoenixMuted
    }
}
