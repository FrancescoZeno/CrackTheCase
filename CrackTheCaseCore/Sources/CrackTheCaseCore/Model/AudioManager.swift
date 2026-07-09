import Foundation
import AVFoundation

/// Background-music playback, switching tracks as the game moves through
/// `GamePhase`. Lives in Core (so both targets can build it) but is only
/// ever actually driven from the tvOS `ContentView` — the shared board is
/// the one screen everyone's looking at, so it owns the room's music;
/// wiring this into the iOS `ContentView` too would layer a second, out-of-
/// sync copy on top from every connected phone. See
/// `GameSettings.isMusicEnabled`'s doc comment.
///
/// Looks tracks up in `Bundle.main` — the same "look for a bundled asset,
/// silently fall back if it isn't there" pattern already used for the video
/// backgrounds (see `LoopingVideoBackground`/`homeScreen`'s own
/// `Bundle.main.url(forResource:withExtension:)` calls). `maingame.mp3`/
/// `victory.mp3`/`defeat.mp3`/`blackout.mp3` live directly in
/// `CrackTheCase/` (the tvOS target's own folder) — an Xcode 16 file-
/// system-synchronized group, so dropping a file in there is enough to
/// bundle it as a resource, no `project.pbxproj` edit needed. The
/// `Bundle.main` fallback still matters beyond that: it keeps this manager
/// harmless (a silent no-op instead of a crash) if a track is ever missing
/// or renamed.
///
/// A plain class (not `@Observable`) — nothing reads its state back into
/// SwiftUI; views only ever call `play(for:)`/`refreshMuteState()` from
/// `onChange`/`onAppear`.
@MainActor
public final class AudioManager {
    public static let shared = AudioManager()

    /// One named track per mood the game needs music for. The raw value is
    /// the bundled resource's base filename (extension-agnostic — see
    /// `url(for:)`).
    public enum Track: String, CaseIterable, Sendable {
        case mainGame = "maingame"
        case victory
        case defeat
        case blackout
    }

    private var player: AVAudioPlayer?
    private var currentTrack: Track?

    private init() {}

    /// Convenience for phase-driven call sites: looks up the right track
    /// for `phase` via `Self.track(for:)` and plays it, or does nothing for
    /// phases that don't have music of their own (see that method's doc
    /// comment) — deliberately not `stop()`, so e.g. `.lobby` doesn't cut
    /// off `.mainGame` still fading out from a `playAgain()` that briefly
    /// bounced through it.
    public func play(for phase: GamePhase) {
        guard let track = Self.track(for: phase) else { return }
        play(track)
    }

    /// Starts looping `track`, unless it's already the one playing — avoids
    /// an audible restart every time `GamePhase` changes to another phase
    /// that maps to the same track (e.g. every round's `.minigame` →
    /// `.roomSelection` → `.notebook` loop all map to `.mainGame`).
    /// Silently does nothing if `GameSettings.isMusicEnabled` is off, or if
    /// the track isn't bundled yet — see the type's doc comment.
    public func play(_ track: Track) {
        guard GameSettings.isMusicEnabled() else {
            stop()
            return
        }
        guard currentTrack != track else { return }
        guard let url = Self.url(for: track) else {
            currentTrack = nil
            player = nil
            return
        }
        do {
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.numberOfLoops = -1
            newPlayer.volume = 0.5
            newPlayer.prepareToPlay()
            newPlayer.play()
            player = newPlayer
            currentTrack = track
        } catch {
            print("AudioManager: failed to play \(track.rawValue): \(error)")
            player = nil
            currentTrack = nil
        }
    }

    public func stop() {
        player?.stop()
        player = nil
        currentTrack = nil
    }

    /// Re-evaluates playback against the current `GameSettings.isMusicEnabled`
    /// value — call this right after the player flips the Music toggle in
    /// `SettingsSheet`, since nothing else re-checks it once a track is
    /// already playing (or already silent).
    public func refreshMuteState() {
        guard let trackToRestore = currentTrack else { return }
        if !GameSettings.isMusicEnabled() {
            stop()
        } else if player == nil {
            play(trackToRestore)
        }
    }

    /// Maps a `GamePhase` to the track that should be playing during it.
    /// `nil` means "this phase has no music of its own" (the pre-game
    /// phases, and the terminal `.notEnoughPlayers` interruption) — callers
    /// should leave whatever's already playing alone rather than cut it,
    /// which is why `play(for:)` no-ops instead of stopping on `nil`.
    public static func track(for phase: GamePhase) -> Track? {
        switch phase {
        case .victory: return .victory
        case .defeat: return .defeat
        case .blackoutReveal, .blackoutTask: return .blackout
        case .minigame, .roomSelection, .notebook, .voting: return .mainGame
        case .connecting, .lobby, .starting, .introVideo, .rules, .notEnoughPlayers: return nil
        }
    }

    /// Resolves `track` to a bundled file URL, trying the extensions most
    /// likely to actually be used for a compressed music loop, in roughly
    /// that priority order.
    private static func url(for track: Track) -> URL? {
        for ext in ["m4a", "mp3", "wav", "caf"] {
            if let url = Bundle.main.url(forResource: track.rawValue, withExtension: ext) {
                return url
            }
        }
        return nil
    }
}
