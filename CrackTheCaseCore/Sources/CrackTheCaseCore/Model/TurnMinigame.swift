import Foundation

/// Which of the 12 turn-order minigames plays during `.minigame`. Re-rolled
/// at random every time `GameSession.beginMinigame()` runs, so a different
/// one can come up each round — unlike `BlackoutMinigame`, which is chosen
/// once for the whole game.
public enum TurnMinigame: String, Codable, Sendable, CaseIterable {
    /// Memorize a 5-digit sequence shown briefly, then re-enter it.
    case numberMemory
    /// Hold to fill a circular gauge, release the instant it's full.
    case holdRelease
    /// Tap 9 shuffled numbers in ascending order before time runs out.
    case tapInOrder
    /// Rotate two linked concentric rings until their marks align.
    case magneticRings
    /// Shake the phone to charge a battery to 100%.
    case shakeCharge
    /// Drag a card along a track at a steady pace — not too fast, not too slow.
    case swipeCardPace
    /// Match pairs of crime-scene icons; a wrong pair flips everything back
    /// face-down without pausing the clock.
    case crimeMemoryMatch
    /// Drag an eye icon to reveal a hidden captcha letter, then pick it.
    case captchaReveal
    /// Tilt the phone to keep a reticle over a drifting target for 4 seconds.
    case tiltAim
    /// Mash two side buttons to push a rising indicator to the top before
    /// gravity pulls it back down.
    case buttonMashing
    /// Scratch off a digital coating to reveal a 4-digit PIN, then enter it.
    case scratchPin
    /// Swipe right on valid cards and left on expired ones, 10 in a row.
    case validCardSwipe
}
