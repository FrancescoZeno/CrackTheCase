import SwiftUI

/// The `keyFitting` turn-order minigame: drag two split key halves
/// together — their teeth interlock to reveal a hidden 3-letter code, which
/// the player then types on a letter grid. Calls `onComplete` once the
/// correct code is entered.
struct TurnKeyFittingView: View {
    let onComplete: () -> Void

    @State private var posLeftKey: CGSize = .zero
    @State private var dragLeftKey: CGSize = .zero
    private let startXLeftKey: CGFloat = 25
    private let startYLeftKey: CGFloat = 30

    @State private var posRightKey: CGSize = .zero
    @State private var dragRightKey: CGSize = .zero
    private let startXRightKey: CGFloat = -25
    private let startYRightKey: CGFloat = -30

    @State private var isSnapped: Bool = false
    @State private var hasStartedDragging: Bool = false
    private let snapThreshold: CGFloat = 35.0

    @State private var enteredCode: String = ""
    @State private var isCodeCorrect: Bool?
    @State private var lastPressedLetter: String?

    private let letters = ["A", "D", "E", "F", "H", "I", "K", "L", "M"]
    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
    private let secretCode = "FKD"

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                Color(white: 0.85).ignoresSafeArea()

                ZStack {
                    KeyFittingCombinedKey()
                        .clipShape(KeyFittingSplitMask(isLeft: false))

                    if !hasStartedDragging {
                        Image(systemName: "hand.point.up.left.fill")
                            .font(.system(size: 40)).foregroundStyle(.white).shadow(color: .black, radius: 2)
                            .offset(x: -50, y: 120).modifier(KeyFittingPulseAnimation())
                    }
                }
                .offset(x: startXRightKey, y: startYRightKey)
                .offset(x: posRightKey.width + dragRightKey.width, y: posRightKey.height + dragRightKey.height)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if !isSnapped {
                                hasStartedDragging = true
                                dragRightKey = value.translation
                            }
                        }
                        .onEnded { _ in
                            if !isSnapped {
                                posRightKey.width += dragRightKey.width
                                posRightKey.height += dragRightKey.height
                                dragRightKey = .zero
                                checkSnap()
                            }
                        }
                )
                .zIndex(1)

                ZStack {
                    KeyFittingCombinedKey()
                        .clipShape(KeyFittingSplitMask(isLeft: true))

                    if !hasStartedDragging {
                        Image(systemName: "hand.point.down.right.fill")
                            .font(.system(size: 40)).foregroundStyle(.white).shadow(color: .black, radius: 2)
                            .offset(x: 50, y: 120).modifier(KeyFittingPulseAnimation())
                    }
                }
                .offset(x: startXLeftKey, y: startYLeftKey)
                .offset(x: posLeftKey.width + dragLeftKey.width, y: posLeftKey.height + dragLeftKey.height)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if !isSnapped {
                                hasStartedDragging = true
                                dragLeftKey = value.translation
                            }
                        }
                        .onEnded { _ in
                            if !isSnapped {
                                posLeftKey.width += dragLeftKey.width
                                posLeftKey.height += dragLeftKey.height
                                dragLeftKey = .zero
                                checkSnap()
                            }
                        }
                )
                .zIndex(1)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 25) {
                VStack(spacing: 8) {
                    if isCodeCorrect == true {
                        Text("CORRECT")
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .foregroundStyle(.phoenixGreen)
                            .padding(.bottom, 10)
                    } else {
                        Text("ENTER CODE")
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundStyle(.phoenixMuted)
                    }

                    HStack(spacing: 12) {
                        Text(codeDisplayChar(at: 0))
                        Text(codeDisplayChar(at: 1))
                        Text(codeDisplayChar(at: 2))
                    }
                    .font(.system(size: 40, weight: .bold, design: .monospaced))
                    .foregroundStyle(codeDisplayColor())
                }
                .padding(.top, 40)

                Spacer()

                LazyVGrid(columns: columns, spacing: 25) {
                    ForEach(letters, id: \.self) { letter in
                        Text(letter)
                            .font(.system(size: 45, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                            .opacity(lastPressedLetter == letter ? 0.3 : 1.0)
                            .scaleEffect(lastPressedLetter == letter ? 1.1 : 1.0)
                            .onTapGesture {
                                pressLetter(letter)
                            }
                    }
                }
                .padding(.horizontal, 30)

                Spacer()
            }
            .frame(width: 340)
            .frame(maxHeight: .infinity)
            .background(Color.phoenixBackground.ignoresSafeArea())
        }
    }

    private func checkSnap() {
        let absXLeftKey = startXLeftKey + posLeftKey.width
        let absYLeftKey = startYLeftKey + posLeftKey.height

        let absXRightKey = startXRightKey + posRightKey.width
        let absYRightKey = startYRightKey + posRightKey.height

        let distanceX = abs(absXLeftKey - absXRightKey)
        let distanceY = abs(absYLeftKey - absYRightKey)

        if distanceX < snapThreshold && distanceY < snapThreshold {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()

            let midX = (absXLeftKey + absXRightKey) / 2
            let midY = (absYLeftKey + absYRightKey) / 2

            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                posLeftKey = CGSize(width: midX - startXLeftKey, height: midY - startYLeftKey)
                posRightKey = CGSize(width: midX - startXRightKey, height: midY - startYRightKey)
                isSnapped = true
            }
        }
    }

    private func pressLetter(_ letter: String) {
        guard isSnapped, isCodeCorrect != true, enteredCode.count < 3 else { return }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        withAnimation(.none) {
            lastPressedLetter = letter
            enteredCode.append(letter)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { lastPressedLetter = nil }

        if enteredCode.count == 3 {
            if enteredCode == secretCode {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                withAnimation { isCodeCorrect = true }
                onComplete()
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                withAnimation { isCodeCorrect = false }

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    withAnimation {
                        enteredCode = ""
                        isCodeCorrect = nil
                    }
                }
            }
        }
    }

    private func codeDisplayChar(at index: Int) -> String {
        if enteredCode.count > index {
            let start = enteredCode.index(enteredCode.startIndex, offsetBy: index)
            return String(enteredCode[start])
        }
        return "_"
    }

    private func codeDisplayColor() -> Color {
        if isCodeCorrect == true { return .phoenixGreen }
        if isCodeCorrect == false { return .phoenixDestructive }
        return .white
    }
}

private struct KeyFittingCombinedKey: View {
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                HStack(spacing: 20) {
                    Circle().stroke(lineWidth: 12).frame(width: 45, height: 45)
                    Circle().stroke(lineWidth: 12).frame(width: 45, height: 45)
                }
                .padding(.bottom, 10)

                KeyFittingOuterShape()
                    .fill(Color.black)
                    .frame(width: 140, height: 280)
            }

            VStack(spacing: 8) {
                Text("F")
                Text("K")
                Text("D")
            }
            .font(.system(size: 65, weight: .black, design: .default))
            .foregroundColor(.black)
            .blendMode(.destinationOut)
            .offset(y: 35)
        }
        .compositingGroup()
        .frame(width: 160, height: 380)
    }
}

private struct KeyFittingOuterShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        path.move(to: CGPoint(x: 10, y: 0))
        path.addLine(to: CGPoint(x: w - 10, y: 0))
        path.addLine(to: CGPoint(x: w - 10, y: 40))
        path.addLine(to: CGPoint(x: w, y: 40))
        path.addLine(to: CGPoint(x: w, y: 70))
        path.addLine(to: CGPoint(x: w - 10, y: 70))
        path.addLine(to: CGPoint(x: w - 10, y: 180))
        path.addLine(to: CGPoint(x: w, y: 180))
        path.addLine(to: CGPoint(x: w, y: 210))
        path.addLine(to: CGPoint(x: w - 10, y: 210))
        path.addLine(to: CGPoint(x: w - 10, y: h))
        path.addLine(to: CGPoint(x: 10, y: h))
        path.addLine(to: CGPoint(x: 10, y: 140))
        path.addLine(to: CGPoint(x: 0, y: 140))
        path.addLine(to: CGPoint(x: 0, y: 110))
        path.addLine(to: CGPoint(x: 10, y: 110))
        path.addLine(to: CGPoint(x: 10, y: 0))
        path.closeSubpath()
        return path
    }
}

private struct KeyFittingSplitMask: Shape {
    var isLeft: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midX = rect.width / 2

        path.move(to: CGPoint(x: midX, y: 0))

        path.addLine(to: CGPoint(x: midX, y: 30))
        path.addLine(to: CGPoint(x: midX - 35, y: 30))
        path.addLine(to: CGPoint(x: midX - 35, y: 60))
        path.addLine(to: CGPoint(x: midX + 30, y: 60))

        path.addLine(to: CGPoint(x: midX + 30, y: 100))
        path.addLine(to: CGPoint(x: midX - 25, y: 100))
        path.addLine(to: CGPoint(x: midX - 25, y: 140))
        path.addLine(to: CGPoint(x: midX + 35, y: 140))

        path.addLine(to: CGPoint(x: midX + 35, y: 180))
        path.addLine(to: CGPoint(x: midX - 30, y: 180))
        path.addLine(to: CGPoint(x: midX - 30, y: 220))
        path.addLine(to: CGPoint(x: midX + 20, y: 220))

        path.addLine(to: CGPoint(x: midX + 20, y: 260))
        path.addLine(to: CGPoint(x: midX, y: 260))

        path.addLine(to: CGPoint(x: midX, y: rect.height))

        if isLeft {
            path.addLine(to: CGPoint(x: 0, y: rect.height))
            path.addLine(to: CGPoint(x: 0, y: 0))
        } else {
            path.addLine(to: CGPoint(x: rect.width, y: rect.height))
            path.addLine(to: CGPoint(x: rect.width, y: 0))
        }

        path.closeSubpath()
        return path
    }
}

private struct KeyFittingPulseAnimation: ViewModifier {
    @State private var isPulsing = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.1 : 0.9)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}
