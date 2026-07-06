import SwiftUI

/// The `scratchPin` turn-order minigame: scratch off a digital coating to
/// reveal a hidden 4-digit PIN, then enter it on a numpad. Calls
/// `onComplete` once the correct PIN is entered.
struct TurnScratchPinView: View {
    let onComplete: () -> Void

    @State private var secretPin = ""
    @State private var feedbackMessage = "Ready when you are"
    @State private var feedbackColor: Color = .phoenixMuted
    @State private var isCompleted = false

    @State private var erasedTiles: Set<Int> = []
    private let rows = 16
    private let columns = 36
    private let totalTiles: Int

    private let areaWidth: CGFloat = 320
    private let areaHeight: CGFloat = 120

    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
        self.totalTiles = rows * columns
    }

    private var scratchProgress: Double {
        Double(erasedTiles.count) / Double(totalTiles)
    }

    private var dynamicBlur: CGFloat {
        max(0, 25 - (CGFloat(scratchProgress) * 35))
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 30) {
                VStack(spacing: 15) {
                    Text("Bypass Door PIN")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(.phoenixGold)

                    MinigameInstructionText(text: "Rub the panel to reveal the hidden PIN, then type it in on the right.")

                    Text(feedbackMessage)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(feedbackColor)
                        .multilineTextAlignment(.center)
                        .frame(height: 40)

                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.phoenixCard)
                            .frame(width: areaWidth, height: areaHeight)

                        Text(secretPin)
                            .font(.system(size: 42, weight: .black, design: .monospaced))
                            .foregroundStyle(Color.phoenixGold.opacity(max(0.1, scratchProgress * 1.2)))
                            .tracking(10)
                            .blur(radius: dynamicBlur)

                        VStack(spacing: 0) {
                            ForEach(0..<rows, id: \.self) { r in
                                HStack(spacing: 0) {
                                    ForEach(0..<columns, id: \.self) { c in
                                        let tileId = (r * columns) + c
                                        Rectangle()
                                            .fill(Color.white.opacity(0.1))
                                            .opacity(erasedTiles.contains(tileId) ? 0 : 1)
                                    }
                                }
                            }
                        }
                        .frame(width: areaWidth, height: areaHeight)
                        .cornerRadius(12)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    guard !isCompleted else { return }
                                    eraseTile(at: value.location)
                                }
                        )
                    }
                    .frame(width: areaWidth, height: areaHeight)

                    Text("Coating removed: \(Int(scratchProgress * 100))%")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.phoenixMuted)
                }
                .frame(width: geometry.size.width * 0.55)

                Divider().background(Color.white.opacity(0.15))

                VStack(spacing: 10) {
                    Text("Enter PIN")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.phoenixMuted)

                    let gridItems = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
                    let buttons = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "Clear", "0", "Enter"]

                    LazyVGrid(columns: gridItems, spacing: 10) {
                        ForEach(buttons, id: \.self) { label in
                            Button {
                                handleNumpadInput(label)
                            } label: {
                                Text(label)
                                    .font(.system(size: label.count > 1 ? 14 : 20, weight: .bold, design: .rounded))
                                    .foregroundStyle(label == "Enter" ? Color.phoenixGreen : (label == "Clear" ? Color.phoenixDestructive : .white))
                                    .frame(maxWidth: .infinity, minHeight: 45)
                                    .background(Color.white.opacity(0.08))
                                    .cornerRadius(8)
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
                generateNewPin()
            }
        }
    }

    private func eraseTile(at point: CGPoint) {
        guard point.x >= 0 && point.x <= areaWidth && point.y >= 0 && point.y <= areaHeight else { return }

        let tileWidth = areaWidth / CGFloat(columns)
        let tileHeight = areaHeight / CGFloat(rows)

        let col = Int(point.x / tileWidth)
        let row = Int(point.y / tileHeight)

        if col >= 0 && col < columns && row >= 0 && row < rows {
            let tileId = (row * columns) + col

            if !erasedTiles.contains(tileId) {
                erasedTiles.insert(tileId)
                if erasedTiles.count % 6 == 0 {
                    Haptics.impact(.light)
                }
            }
        }
    }

    @State private var currentInput = ""

    private func handleNumpadInput(_ label: String) {
        if label == "Clear" {
            currentInput = ""
            feedbackMessage = "Input cleared."
            feedbackColor = .phoenixMuted
        } else if label == "Enter" {
            if currentInput == secretPin {
                feedbackMessage = "Access granted! Door unlocked."
                feedbackColor = .phoenixGreen
                isCompleted = true
                Haptics.notify(.success)
                onComplete()
            } else {
                feedbackMessage = "Access denied! Wrong PIN entered."
                feedbackColor = .phoenixDestructive
                currentInput = ""
                Haptics.notify(.error)
            }
        } else if currentInput.count < 4 {
            currentInput += label
            feedbackMessage = "Code entered: \(currentInput)"
            feedbackColor = .white
        }
    }

    private func generateNewPin() {
        let num1 = Int.random(in: 0...9)
        let num2 = Int.random(in: 0...9)
        let num3 = Int.random(in: 0...9)
        let num4 = Int.random(in: 0...9)
        secretPin = "\(num1)\(num2)\(num3)\(num4)"

        erasedTiles.removeAll()
        currentInput = ""
        isCompleted = false
        feedbackMessage = "Ready when you are"
        feedbackColor = .phoenixMuted
    }
}
