import SwiftUI
import CrackTheCaseCore

/// Shared neon-glow shadow used by several turn-order minigames (tilt aim,
/// button mashing, valid-card swipe) for their sci-fi/hacker visual style.
extension View {
    func glowEffect(color: Color, radius: CGFloat) -> some View {
        self
            .shadow(color: color.opacity(0.8), radius: radius)
            .shadow(color: color.opacity(0.5), radius: radius / 2)
    }
}

/// A short, plain-English "how to play" callout shown near the header of
/// every turn-order/Black-out minigame. Each of these is a timed,
/// competitive (or, for Black-out, cooperative) mechanic sprung on the
/// player with no tutorial — a one-line reminder keeps the mechanic clear
/// at a glance instead of players having to guess from the visuals alone.
///
/// Deliberately given its own gold-tinted pill background rather than
/// floating as plain muted text: a faint caption is too easy to miss
/// against these minigames' busy, high-contrast visuals, and this needs to
/// read as "important — read me" on first glance, not as decoration.
struct MinigameInstructionText: View {
    let text: String

    var body: some View {
        Label {
            Text(text)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.phoenixGold)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.phoenixGold.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.phoenixGold.opacity(0.55), lineWidth: 1)
        )
    }
}

/// Display name and "how to play" line for every turn-order minigame — the
/// single source of truth reused by `MinigameIntroGate` below and by
/// `MinigameDebugMenuView` (`#if DEBUG`), instead of two hand-maintained
/// copies drifting apart.
extension TurnMinigame {
    var displayTitle: String {
        switch self {
        case .numberMemory: return "Number Memory"
        case .holdRelease: return "Hold & Release"
        case .tapInOrder: return "Tap In Order"
        case .magneticRings: return "Magnetic Rings"
        case .shakeCharge: return "Shake Charge"
        case .swipeCardPace: return "Swipe Card Pace"
        case .crimeMemoryMatch: return "Crime Memory Match"
        case .captchaReveal: return "Captcha Reveal"
        case .tiltAim: return "Tilt Aim"
        case .buttonMashing: return "Button Mashing"
        case .scratchPin: return "Scratch PIN"
        case .validCardSwipe: return "Valid Card Swipe"
        }
    }

    /// Kept word-for-word identical to the `MinigameInstructionText` each
    /// minigame shows internally once playing — this copy is only what the
    /// pre-game `MinigameIntroGate` shows before that view even exists.
    var instructionText: String {
        switch self {
        case .numberMemory: return "Memorize the 5 numbers, then type them back in the same order."
        case .holdRelease: return "Hold the circle and let go the instant it's completely full."
        case .tapInOrder: return "Tap the numbers in order, from 1 to 9, before time runs out."
        case .magneticRings: return "Turn both rings until their marks line up at the top. Turning one moves the other too."
        case .shakeCharge: return "Shake your phone hard until the battery bar fills up to 100%."
        case .swipeCardPace: return "Drag the card all the way across at a steady pace — not too fast, not too slow, and never backwards."
        case .crimeMemoryMatch: return "Tap 2 cards to match all 4 pairs. A wrong pair flips back over, but the clock keeps running!"
        case .captchaReveal: return "Drag the eye to uncover the hidden letter, then tap that letter on the right."
        case .tiltAim: return "Tilt your phone (don't touch the screen) to move the reticle onto the red target for 4 seconds."
        case .buttonMashing: return "Tap both TAP buttons as fast as you can to push the indicator to the top."
        case .scratchPin: return "Rub the panel to reveal the hidden PIN, then type it in on the right."
        case .validCardSwipe: return "Swipe right on VALID keys, left on EXPIRED ones — 10 in a row."
        }
    }
}

/// Same idea as `TurnMinigame.displayTitle`/`.instructionText` above, for
/// the 3 Black-out emergency tasks.
extension BlackoutMinigame {
    var displayTitle: String {
        switch self {
        case .lightRegulator: return "Light Regulator"
        case .overvoltageWhack: return "Overvoltage Whack"
        case .pistonSync: return "Piston Sync"
        }
    }

    var instructionText: String {
        switch self {
        case .lightRegulator: return "The lights won't come back until the team matches the target!"
        case .overvoltageWhack: return "Tap each spark as soon as it lights up, before it fades away."
        case .pistonSync: return "Tap each piston while it's in the green zone to lock it, then pull the lever."
        }
    }
}

/// Shows a minigame's "how to play" instruction on its own for at least
/// `introDuration` seconds before the actual minigame is even constructed.
/// Competitive players tend to blow straight past a same-screen instruction
/// without reading it — and some minigames start a timer or race the
/// instant they appear (e.g. `TurnTapInOrderView`'s 7-second countdown
/// begins on the very first frame), leaving zero time to read anything.
/// Delaying construction of `game()` itself, rather than just overlaying
/// content on top of it, means no minigame's internal `Timer`/countdown can
/// start early either — it simply doesn't exist yet.
///
/// Only wraps minigames that don't already have their own multi-second
/// pre-game phase (`TurnCrimeMemoryMatchView`, `TurnButtonMashingView`,
/// `TurnTiltAimView`, `TurnValidCardSwipeView` all have their own countdown
/// already and show their instruction during it instead — wrapping those
/// too would just stack a second, redundant wait on top).
struct MinigameIntroGate<Game: View>: View {
    let title: String
    let instruction: String
    @ViewBuilder let game: () -> Game

    private static var introDuration: Int { 5 }

    @State private var secondsRemaining = MinigameIntroGate.introDuration
    @State private var isReady = false
    @State private var timer: Timer?

    var body: some View {
        Group {
            if isReady {
                game()
            } else {
                introContent
            }
        }
        .onAppear { startIntro() }
        .onDisappear { timer?.invalidate() }
    }

    private var introContent: some View {
        ZStack {
            Color.phoenixBackground.ignoresSafeArea()

            VStack(spacing: 20) {
                Text(title)
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(.phoenixGold)

                MinigameInstructionText(text: instruction)
                    .padding(.horizontal, 60)

                Text("Get ready… \(secondsRemaining)")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.phoenixMuted)
            }
        }
    }

    private func startIntro() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
            if secondsRemaining > 1 {
                secondsRemaining -= 1
            } else {
                t.invalidate()
                withAnimation {
                    isReady = true
                }
            }
        }
    }
}
