import SwiftUI
import Combine

/// The `pistonSync` Black-out task: tap each piston while it's in its green
/// zone to lock it, then pull the lever. Completed independently by each
/// player — calls `onComplete` once the lever is thrown.
struct BlackoutPistonSyncView: View {
    let onComplete: () -> Void

    fileprivate struct Piston: Identifiable {
        let id = UUID()
        var offset: CGFloat
        var speed: CGFloat
        var movingUp: Bool
        var isLocked: Bool = false
    }

    @State private var pistons: [Piston] = [
        Piston(offset: 80, speed: 3.5, movingUp: true),
        Piston(offset: -50, speed: 4.8, movingUp: false),
        Piston(offset: 20, speed: 2.9, movingUp: true),
        Piston(offset: -90, speed: 5.5, movingUp: false),
    ]

    private let engineTimer = Timer.publish(every: 0.016, on: .main, in: .common).autoconnect()
    private let countdownTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    @State private var timeRemaining = 20
    @State private var isPowerOn = false
    @State private var leverOffset: CGFloat = 0
    @State private var flashRedTimer = false

    // Sized to fit a phone's short landscape height — see the `HStack`
    // layout below, which puts the pistons and the lever side by side
    // instead of stacking everything vertically (the original vertical
    // stack of status + pistons + label + lever overflowed landscape).
    private let trackHeight: CGFloat = 130
    private let headHeight: CGFloat = 30
    private let maxOffset: CGFloat = 50
    private let targetZoneRange: ClosedRange<CGFloat> = -11...11
    private let leverTrackHeight: CGFloat = 120
    private let leverMaxOffset: CGFloat = 90
    private let leverSuccessThreshold: CGFloat = 68

    private var allLocked: Bool {
        pistons.allSatisfy(\.isLocked)
    }

    var body: some View {
        ZStack {
            Color.phoenixBackground.ignoresSafeArea()

            HStack(spacing: 28) {
                VStack(spacing: 14) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(timeRemaining <= 5 && !allLocked ? .phoenixDestructive : .phoenixGold)
                            .opacity(flashRedTimer ? 1.0 : 0.5)

                        Text(allLocked ? "SYSTEM STABLE" : "OVERLOAD IN: \(timeRemaining)s")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundStyle(allLocked ? .phoenixGreen : (timeRemaining <= 5 ? .phoenixDestructive : .phoenixGold))
                    }
                    .opacity(isPowerOn ? 0 : 1)

                    if !allLocked {
                        MinigameInstructionText(text: "Tap each piston while it's in the green zone to lock it, then pull the lever.")
                    }

                    HStack(spacing: 14) {
                        ForEach(pistons.indices, id: \.self) { index in
                            PistonColumn(
                                piston: pistons[index],
                                trackHeight: trackHeight,
                                headHeight: headHeight,
                                isPowerOn: isPowerOn
                            )
                            .onTapGesture {
                                handlePistonTap(at: index)
                            }
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.phoenixCard)
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1))
                    )
                }

                VStack(spacing: 10) {
                    Text("MAIN POWER")
                        .font(.system(size: 15, weight: .black, design: .monospaced))
                        .foregroundStyle(allLocked ? .phoenixGold : .phoenixMuted)

                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.black)
                            .frame(width: 36, height: leverTrackHeight)

                        VStack {
                            Circle()
                                .fill(allLocked ? Color.phoenixGreen : Color.phoenixDestructive)
                                .frame(width: 14, height: 14)
                                .opacity(allLocked ? 1.0 : (flashRedTimer ? 1.0 : 0.3))
                                .padding(.top, 10)
                            Spacer()
                        }

                        ZStack {
                            Rectangle()
                                .fill(Color.phoenixMuted)
                                .frame(width: 58, height: 28)
                                .cornerRadius(5)

                            HStack(spacing: 0) {
                                ForEach(0..<4) { _ in
                                    Rectangle().fill(Color.phoenixGold).frame(width: 5.5)
                                    Rectangle().fill(Color.black).frame(width: 5.5)
                                }
                            }
                            .mask(Rectangle().frame(width: 58, height: 28).cornerRadius(5))
                        }
                        .offset(y: -leverTrackHeight / 2 + 15 + leverOffset)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    guard allLocked && !isPowerOn else { return }
                                    let newOffset = value.translation.height
                                    if newOffset > 0 && newOffset <= leverMaxOffset {
                                        leverOffset = newOffset
                                    }
                                }
                                .onEnded { _ in
                                    guard allLocked && !isPowerOn else { return }
                                    if leverOffset > leverSuccessThreshold {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                                            leverOffset = leverMaxOffset
                                        }
                                        triggerPowerOn()
                                    } else {
                                        withAnimation(.spring()) {
                                            leverOffset = 0
                                        }
                                    }
                                }
                        )
                    }
                    .frame(width: 80, height: leverTrackHeight + 30)
                    .background(Color.phoenixCard)
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
                }
            }
            .padding(.horizontal, 20)
        }
        .onReceive(engineTimer) { _ in
            guard !isPowerOn else { return }
            updatePistons()

            if !allLocked {
                let time = Date().timeIntervalSince1970
                flashRedTimer = time.truncatingRemainder(dividingBy: 0.8) < 0.4
            } else {
                flashRedTimer = true
            }
        }
        .onReceive(countdownTimer) { _ in
            guard !allLocked && !isPowerOn else { return }
            if timeRemaining > 0 {
                timeRemaining -= 1
            } else {
                triggerOverload()
            }
        }
    }

    private func updatePistons() {
        for i in pistons.indices {
            guard !pistons[i].isLocked else { continue }
            if pistons[i].movingUp {
                pistons[i].offset -= pistons[i].speed
                if pistons[i].offset <= -maxOffset { pistons[i].movingUp = false }
            } else {
                pistons[i].offset += pistons[i].speed
                if pistons[i].offset >= maxOffset { pistons[i].movingUp = true }
            }
        }
    }

    private func handlePistonTap(at index: Int) {
        guard !pistons[index].isLocked && !isPowerOn else { return }

        if targetZoneRange.contains(pistons[index].offset) {
            pistons[index].offset = 0
            pistons[index].isLocked = true
            Haptics.impact(.heavy)
            if allLocked {
                Haptics.notify(.success)
            }
        } else {
            Haptics.notify(.error)
        }
    }

    private func triggerOverload() {
        Haptics.notify(.error)
        withAnimation(.easeInOut(duration: 0.3)) {
            for i in pistons.indices {
                pistons[i].isLocked = false
                pistons[i].speed = CGFloat.random(in: 2.5...6.0)
            }
            timeRemaining = 20
        }
    }

    private func triggerPowerOn() {
        Haptics.impact(.heavy)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.easeOut(duration: 0.8)) {
                isPowerOn = true
            }
            Haptics.notify(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                onComplete()
            }
        }
    }
}

private struct PistonColumn: View {
    let piston: BlackoutPistonSyncView.Piston
    let trackHeight: CGFloat
    let headHeight: CGFloat
    let isPowerOn: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black)
                .frame(width: 44, height: trackHeight)

            Rectangle()
                .fill(Color.phoenixGreen.opacity(isPowerOn ? 0 : 0.3))
                .frame(width: 44, height: 32)
                .overlay(
                    Rectangle().stroke(Color.phoenixGreen, lineWidth: isPowerOn ? 0 : 2)
                )

            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(LinearGradient(colors: [Color(white: 0.6), Color(white: 0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 36, height: headHeight)

                Circle()
                    .fill(isPowerOn ? Color.phoenixMuted : (piston.isLocked ? Color.phoenixGreen : Color.phoenixGold))
                    .frame(width: 12, height: 12)
            }
            .offset(y: piston.offset)
        }
    }
}
