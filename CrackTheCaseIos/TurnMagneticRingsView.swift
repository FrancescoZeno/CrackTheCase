import SwiftUI

/// The `magneticRings` turn-order minigame: rotate two linked concentric
/// rings — dragging one also nudges the other — until both marks line up
/// at the top. Calls `onComplete` once aligned.
struct TurnMagneticRingsView: View {
    let onComplete: () -> Void

    @State private var outerAngle: Double = Double.random(in: 45...315)
    @State private var innerAngle: Double = Double.random(in: 45...315)
    @State private var isSolved = false

    @State private var activeRing: RingType = .none
    @State private var previousDragAngle: Double = 0

    private let outerRadius: CGFloat = 120
    private let innerRadius: CGFloat = 80
    private let tolerance: Double = 12.0

    private enum RingType {
        case outer, inner, none
    }

    var body: some View {
        ZStack {
            Color.phoenixBackground.ignoresSafeArea()

            HStack(spacing: 20) {
                VStack(spacing: 20) {
                    Text("Magnetic Cracking")
                        .font(.title)
                        .bold()
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    VStack(spacing: 12) {
                        Text(isSolved ? "Firewall Bypassed!" : "Interference Detected")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundStyle(isSolved ? .phoenixGreen : .phoenixGold)

                        Text(isSolved ? "Data access granted." : "The magnetic fields are linked.\nRotating one ring affects the other.")
                            .font(.subheadline)
                            .foregroundStyle(.phoenixMuted)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.leading, 20)

                Divider()
                    .background(Color.white.opacity(0.15))
                    .padding(.vertical, 40)

                GeometryReader { geometry in
                    let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)

                    Color.white.opacity(0.001)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    guard !isSolved else { return }
                                    handleDragChange(value: value, center: center)
                                }
                                .onEnded { _ in
                                    activeRing = .none
                                    checkCompletion()
                                }
                        )

                    ZStack {
                        VStack {
                            Capsule()
                                .fill(isSolved ? Color.phoenixGreen : Color.white.opacity(0.3))
                                .frame(width: 8, height: 25)
                            Spacer()
                        }
                        .frame(height: outerRadius * 2 + 50)

                        ZStack {
                            Circle().stroke(Color.white.opacity(0.15), lineWidth: 20)
                            Circle()
                                .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 10]))
                                .foregroundStyle(.white.opacity(0.3))
                                .frame(width: outerRadius * 2 + 30, height: outerRadius * 2 + 30)
                            Circle()
                                .trim(from: 0.0, to: 0.05)
                                .stroke(isSolved ? Color.phoenixGreen : Color.cyan, style: StrokeStyle(lineWidth: 20, lineCap: .round))
                                .rotationEffect(.degrees(-99))
                        }
                        .frame(width: outerRadius * 2, height: outerRadius * 2)
                        .rotationEffect(.degrees(outerAngle))

                        ZStack {
                            Circle().stroke(Color.white.opacity(0.15), lineWidth: 20)
                            Circle()
                                .trim(from: 0.0, to: 0.05)
                                .stroke(isSolved ? Color.phoenixGreen : Color.blue, style: StrokeStyle(lineWidth: 20, lineCap: .round))
                                .rotationEffect(.degrees(-99))
                        }
                        .frame(width: innerRadius * 2, height: innerRadius * 2)
                        .rotationEffect(.degrees(innerAngle))

                        Circle()
                            .fill(isSolved ? Color.phoenixGreen.opacity(0.2) : Color.white.opacity(0.08))
                            .frame(width: 40, height: 40)
                            .overlay(
                                Circle().stroke(isSolved ? Color.phoenixGreen : Color.white.opacity(0.4), lineWidth: 2)
                            )
                    }
                    .position(center)
                    .allowsHitTesting(false)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 30)
        }
    }

    private func handleDragChange(value: DragGesture.Value, center: CGPoint) {
        let vector = CGVector(dx: value.location.x - center.x, dy: value.location.y - center.y)
        let distance = sqrt(vector.dx * vector.dx + vector.dy * vector.dy)
        let radians = atan2(vector.dy, vector.dx)
        let currentDragAngle = radians * 180 / .pi

        if activeRing == .none {
            if distance > innerRadius + 10 {
                activeRing = .outer
            } else if distance > 20 {
                activeRing = .inner
            } else {
                return
            }
            previousDragAngle = currentDragAngle
            return
        }

        var angleDelta = currentDragAngle - previousDragAngle
        if angleDelta > 180 { angleDelta -= 360 }
        if angleDelta < -180 { angleDelta += 360 }

        if activeRing == .outer {
            outerAngle += angleDelta
            innerAngle -= angleDelta * 0.5
        } else if activeRing == .inner {
            innerAngle += angleDelta
            outerAngle += angleDelta * 0.3
        }

        previousDragAngle = currentDragAngle
    }

    private func checkCompletion() {
        let normOuter = normalize(angle: outerAngle)
        let normInner = normalize(angle: innerAngle)

        let outerIsAligned = normOuter < tolerance || normOuter > (360 - tolerance)
        let innerIsAligned = normInner < tolerance || normInner > (360 - tolerance)

        if outerIsAligned && innerIsAligned {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                outerAngle = 0
                innerAngle = 0
                isSolved = true
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onComplete()
        }
    }

    private func normalize(angle: Double) -> Double {
        var a = angle.truncatingRemainder(dividingBy: 360)
        if a < 0 { a += 360 }
        return a
    }
}
