import SwiftUI

/// The `keyFitting` turn-order minigame: drag two split key halves
/// together — their teeth interlock to reveal a hidden 3-letter code, which
/// the player then types on a letter grid. Calls `onComplete` once the
/// correct code is entered.
struct TurnKeyFittingView: View {
    let onComplete: () -> Void

    @State private var posLeftKey: CGSize = .zero
    @State private var dragLeftKey: CGSize = .zero
    private let startXLeftKey: CGFloat = 25 * keyFittingScale
    private let startYLeftKey: CGFloat = 30 * keyFittingScale

    @State private var posRightKey: CGSize = .zero
    @State private var dragRightKey: CGSize = .zero
    private let startXRightKey: CGFloat = -25 * keyFittingScale
    private let startYRightKey: CGFloat = -30 * keyFittingScale

    @State private var isSnapped: Bool = false
    @State private var hasStartedDragging: Bool = false
    private let snapThreshold: CGFloat = 35.0 * keyFittingScale

    @State private var enteredCode: String = ""
    @State private var isCodeCorrect: Bool?
    @State private var lastPressedLetter: String?

    private let letters = ["A", "D", "E", "F", "H", "I", "K", "L", "M"]
    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
    private let secretCode = "FKD"

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                Color.phoenixBackground.ignoresSafeArea()

                ZStack {
                    KeyFittingCombinedKey()
                        .clipShape(KeyFittingSplitMask(isLeft: false))

                    if !hasStartedDragging {
                        Image(systemName: "hand.point.up.left.fill")
                            .font(.system(size: 40 * keyFittingScale)).foregroundStyle(.white).shadow(color: .black, radius: 2)
                            .offset(x: -50 * keyFittingScale, y: 120 * keyFittingScale).modifier(KeyFittingPulseAnimation())
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
                            .font(.system(size: 40 * keyFittingScale)).foregroundStyle(.white).shadow(color: .black, radius: 2)
                            .offset(x: 50 * keyFittingScale, y: 120 * keyFittingScale).modifier(KeyFittingPulseAnimation())
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
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(.phoenixGreen)
                            .padding(.bottom, 10)
                    } else if isSnapped {
                        Text("ENTER CODE")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.phoenixMuted)
                    } else {
                        MinigameInstructionText(text: "Drag the two key halves together on the left. They'll reveal a 3-letter code to type in here.")
                            .padding(.horizontal, 20)
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
                            .font(.system(size: 45, weight: .bold, design: .rounded))
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
            Haptics.impact(.heavy)

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

        Haptics.impact(.light)

        withAnimation(.none) {
            lastPressedLetter = letter
            enteredCode.append(letter)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { lastPressedLetter = nil }

        if enteredCode.count == 3 {
            if enteredCode == secretCode {
                Haptics.impact(.heavy)
                withAnimation { isCodeCorrect = true }
                onComplete()
            } else {
                Haptics.notify(.error)
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

/// Scales down the whole key graphic (originally drawn for a 160×380
/// canvas) to fit a phone's short landscape height, which the original size
/// overflowed — parts of the key rendered past the screen's visible bounds,
/// making them unreadable and, since SwiftUI hit-testing doesn't extend
/// past a parent's laid-out frame, hard or impossible to drag. Shared by
/// `TurnKeyFittingView`'s own start offsets/snap threshold/hint icons and by
/// `KeyFittingOuterShape`/`KeyFittingSplitMask` below — their hardcoded path
/// coordinates must scale together, since the mask's zigzag has to line up
/// exactly with the outer shape's teeth for the split-reveal effect to work.
private let keyFittingScale: CGFloat = 0.72

private struct KeyFittingCombinedKey: View {
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                HStack(spacing: 20 * keyFittingScale) {
                    Circle().stroke(Color(white: 0.65), lineWidth: 12 * keyFittingScale).frame(width: 45 * keyFittingScale, height: 45 * keyFittingScale)
                    Circle().stroke(Color(white: 0.65), lineWidth: 12 * keyFittingScale).frame(width: 45 * keyFittingScale, height: 45 * keyFittingScale)
                }
                .padding(.bottom, 10 * keyFittingScale)

                KeyFittingOuterShape()
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.82), Color(white: 0.52)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 140 * keyFittingScale, height: 280 * keyFittingScale)
            }

            VStack(spacing: 8) {
                Text("F")
                Text("K")
                Text("D")
            }
            .font(.system(size: 65 * keyFittingScale, weight: .black, design: .default))
            .foregroundColor(.black)
            .blendMode(.destinationOut)
            .offset(y: 35 * keyFittingScale)
        }
        .compositingGroup()
        .frame(width: 160 * keyFittingScale, height: 380 * keyFittingScale)
    }
}

private struct KeyFittingOuterShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        // Every constant below is the original design's value (drawn for a
        // 140×280 canvas) times `keyFittingScale` — `w`/`h` already reflect
        // the caller's (scaled) frame, but these inset/notch offsets are
        // absolute pixel amounts, not fractions of the frame, so they need
        // scaling explicitly to keep the shape's proportions correct at any
        // size. Must stay in lockstep with `KeyFittingSplitMask` below.
        let m = 10 * keyFittingScale
        let y40 = 40 * keyFittingScale
        let y70 = 70 * keyFittingScale
        let y110 = 110 * keyFittingScale
        let y140 = 140 * keyFittingScale
        let y180 = 180 * keyFittingScale
        let y210 = 210 * keyFittingScale

        path.move(to: CGPoint(x: m, y: 0))
        path.addLine(to: CGPoint(x: w - m, y: 0))
        path.addLine(to: CGPoint(x: w - m, y: y40))
        path.addLine(to: CGPoint(x: w, y: y40))
        path.addLine(to: CGPoint(x: w, y: y70))
        path.addLine(to: CGPoint(x: w - m, y: y70))
        path.addLine(to: CGPoint(x: w - m, y: y180))
        path.addLine(to: CGPoint(x: w, y: y180))
        path.addLine(to: CGPoint(x: w, y: y210))
        path.addLine(to: CGPoint(x: w - m, y: y210))
        path.addLine(to: CGPoint(x: w - m, y: h))
        path.addLine(to: CGPoint(x: m, y: h))
        path.addLine(to: CGPoint(x: m, y: y140))
        path.addLine(to: CGPoint(x: 0, y: y140))
        path.addLine(to: CGPoint(x: 0, y: y110))
        path.addLine(to: CGPoint(x: m, y: y110))
        path.addLine(to: CGPoint(x: m, y: 0))
        path.closeSubpath()
        return path
    }
}

private struct KeyFittingSplitMask: Shape {
    var isLeft: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midX = rect.width / 2
        // Same scaling note as `KeyFittingOuterShape` above — these zigzag
        // offsets are absolute pixel amounts from the original 380-tall
        // design, scaled by `keyFittingScale` so the split boundary still
        // lines up with the outer shape's teeth at the smaller size.
        let dx1 = 35 * keyFittingScale
        let dx2 = 30 * keyFittingScale
        let dx3 = 25 * keyFittingScale
        let dx4 = 20 * keyFittingScale
        let y1 = 30 * keyFittingScale
        let y2 = 60 * keyFittingScale
        let y3 = 100 * keyFittingScale
        let y4 = 140 * keyFittingScale
        let y5 = 180 * keyFittingScale
        let y6 = 220 * keyFittingScale
        let y7 = 260 * keyFittingScale

        path.move(to: CGPoint(x: midX, y: 0))

        path.addLine(to: CGPoint(x: midX, y: y1))
        path.addLine(to: CGPoint(x: midX - dx1, y: y1))
        path.addLine(to: CGPoint(x: midX - dx1, y: y2))
        path.addLine(to: CGPoint(x: midX + dx2, y: y2))

        path.addLine(to: CGPoint(x: midX + dx2, y: y3))
        path.addLine(to: CGPoint(x: midX - dx3, y: y3))
        path.addLine(to: CGPoint(x: midX - dx3, y: y4))
        path.addLine(to: CGPoint(x: midX + dx1, y: y4))

        path.addLine(to: CGPoint(x: midX + dx1, y: y5))
        path.addLine(to: CGPoint(x: midX - dx2, y: y5))
        path.addLine(to: CGPoint(x: midX - dx2, y: y6))
        path.addLine(to: CGPoint(x: midX + dx4, y: y6))

        path.addLine(to: CGPoint(x: midX + dx4, y: y7))
        path.addLine(to: CGPoint(x: midX, y: y7))

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
