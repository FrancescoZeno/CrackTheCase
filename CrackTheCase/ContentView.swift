//
//  ContentView.swift
//  CrackTheCase
//
//  Created by AFP PAR 049 on 01/07/2026.
//

import SwiftUI
import AVKit
import CrackTheCaseCore

/// The board screen shown on the Apple TV: advertises the game
/// over the local network, shows every connected player's avatar/nickname/
/// ready state, and auto-advances into `.starting` once everyone is ready.
struct ContentView: View {
    @State private var host = HostConnectivityService()
    @State private var countdown: Int?
    @State private var showSettings = false
    /// Lets anyone review the rules on demand from the lobby — the
    /// automatic `rulesView` only ever shows once per Apple TV, on its
    /// first game (see `hasSeenOnboarding`), and is otherwise unreachable.
    @State private var showRules = false
    /// Local win-count leaderboard, persisted on this Apple TV across
    /// "Play Again" restarts and app relaunches — see `GameStats.swift`.
    @State private var gameStats = GameStats.load()
    /// Confirmation gate for `quitToHomeButton` — ending a game here ends it
    /// for every connected phone, not just the TV, so it's worth a beat of
    /// friction before it fires.
    @State private var showQuitConfirmation = false
    @Environment(\.scenePhase) private var scenePhase
    /// Lets the intro video and rulebook be skipped automatically from the
    /// second game onward, per the design: both are only mandatory the
    /// first time this Apple TV hosts a game.
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    /// Scopes `.prefersDefaultFocus` on the terminal screens (`victoryView`,
    /// `defeatView`, `notEnoughPlayersView`) so their primary button reliably
    /// gets focus the moment the screen appears, instead of leaving tvOS to
    /// guess (which, without this, likely landed on `quitToHomeButton` — the
    /// only other focusable element, sitting in an unrelated `ZStack` layer
    /// — or somewhere ambiguous, making "Play Again"/"Back to lobby"
    /// unreachable by directional navigation).
    @Namespace private var defaultFocusNamespace

    private static let countdownSeconds = 3
    /// How long the board shows "read your clue on your phone!" after the
    /// last player picks their room, before auto-opening the notebook — long
    /// enough for everyone to read their own private reveal, since every
    /// clue lands on every phone at the same moment (see
    /// `HostConnectivityService`'s batched `.chooseRoom` handling).
    @State private var isAtHome = true
    @State private var isPlayingPreIntro = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isPlayingPreIntro {
                preIntroVideoView
                    .transition(.opacity)
            } else if isAtHome {
                homeScreen
                    .transition(.opacity)
            } else {
                gameContent
                    .transition(.opacity)
            }
        }
        // Attached once here, not inside `homeScreen`/`lobbyView`
        // individually — `showSettings` is set from both screens' own
        // Settings button, but a `.sheet` only presents while attached to a
        // view that's actually on screen. Attaching it only inside
        // `lobbyView` meant pressing Settings from the home screen set the
        // flag with nothing there to present it; it would only pop up later,
        // once `lobbyView` appeared and picked up the already-true state.
        .sheet(isPresented: $showSettings) {
            SettingsSheet()
        }
    }
    
    @ViewBuilder
    private var gameContent: some View {
        ZStack {
            background

            gameContentPhaseView

            // Positioned via nested Spacers, not `.overlay(alignment:)` —
            // on this SDK, an `.overlay`-positioned button cluster left the
            // tvOS focus engine unable to move focus off whichever button
            // had it (arrow presses either did nothing or re-triggered the
            // current button's own action instead of navigating). Plain
            // ZStack/VStack/HStack siblings with Spacers, matching the
            // structure of the (working) home screen buttons, sidesteps it.
            VStack {
                HStack {
                    quitToHomeButton
                    Spacer()
                    GameClockView(deadline: host.session.gameDeadline)
                }
                Spacer()
            }
        }
        .background(quitConfirmationDialog)
        .animation(.easeInOut(duration: 0.3), value: host.session.phase)
        .onAppear {
            host.start()
            #if os(tvOS) || os(iOS)
            UIApplication.shared.isIdleTimerDisabled = true
            #endif
            AudioManager.shared.play(for: host.session.phase)
        }
        .onChange(of: host.session.phase) { _, phase in
            AudioManager.shared.play(for: phase)
        }
        .onChange(of: host.session.canStart) { _, canStart in
            if canStart {
                startCountdown()
            } else {
                countdown = nil
            }
        }
        .onChange(of: host.session.phase) { _, phase in
            // A brief "the case is about to begin" beat, then the story +
            // rules (skipped automatically from the second game onward),
            // then straight into the turn-order minigame.
            guard phase == .starting else { return }
            Task {
                try? await Task.sleep(for: .seconds(2))
                guard host.session.phase == .starting else { return }
                if hasSeenOnboarding {
                    host.beginMinigame()
                } else {
                    host.beginIntroVideo()
                }
            }
        }
        .onChange(of: host.session.allPlayersFinishedMinigame) { _, allDone in
            // Same beat-then-advance pattern: let the finished leaderboard sit
            // on screen briefly before moving into room exploration.
            guard allDone else { return }
            Task {
                try? await Task.sleep(for: .seconds(2))
                guard host.session.allPlayersFinishedMinigame else { return }
                host.beginRoomSelection()
            }
        }
        .onChange(of: host.session.isRoomSelectionComplete) { _, complete in
            // Everyone's clue landed on their phone at the same moment (the
            // host batches all reveals until the last turn is taken) — give
            // them time to actually read it before auto-opening the
            // notebook, no one needs to walk over to the TV and press
            // anything.
            guard complete else { return }
            Task {
                try? await Task.sleep(for: .seconds(10))
                guard host.session.isRoomSelectionComplete else { return }
                host.beginNotebook()
            }
        }
        .onChange(of: host.session.phase) { _, phase in
            // Brief narrative beat, then the emergency task begins.
            guard phase == .blackoutReveal else { return }
            Task {
                try? await Task.sleep(for: .seconds(4))
                guard host.session.phase == .blackoutReveal else { return }
                host.beginBlackoutTask()
            }
        }
        .onChange(of: host.session.allPlayersFinishedBlackoutTask) { _, allDone in
            guard allDone else { return }
            Task {
                try? await Task.sleep(for: .seconds(2))
                guard host.session.allPlayersFinishedBlackoutTask else { return }
                host.beginMinigame()
            }
        }
        .onChange(of: host.session.phase) { _, phase in
            // Credit the win to the local leaderboard the moment the game
            // is solved — persists across "Play Again" and app relaunches.
            guard phase == .victory, let winnerID = host.session.lastAccusation?.playerID else { return }
            gameStats.recordWin(for: winnerID)
            gameStats.save()
        }
        .onChange(of: scenePhase) { _, phase in
            // Pause advertising (not a full disconnect!) when backgrounded,
            // so a stopped app doesn't linger as a "ghost" host — but a
            // transient background transition (e.g. a Siri Remote
            // Home-button tap) must never drop players mid-game. Restart
            // advertising cleanly when active again.
            switch phase {
            case .active:
                host.start()
            case .background:
                host.pauseAdvertising()
            case .inactive:
                break
            @unknown default:
                break
            }
        }
    }

    /// Just the phase → screen dispatch, split out from `gameContent` so the
    /// latter's (unrelated) modifiers — `.overlay`, `.onChange`, etc. — stay
    /// readable instead of trailing a giant `switch`.
    @ViewBuilder
    private var gameContentPhaseView: some View {
        // `Group` (rather than applying `.focusScope` to each case
        // individually) so every phase shares one scope for
        // `.prefersDefaultFocus` — only `victoryView`/`defeatView`/
        // `notEnoughPlayersView` actually use it today, but scoping the
        // whole switch means adding it to a future phase is just one
        // `.prefersDefaultFocus` call, no extra plumbing here.
        Group {
            switch host.session.phase {
            case .connecting, .lobby:
                lobbyView
            case .starting:
                startingView
            case .introVideo:
                introVideoView
            case .rules:
                rulesView
            case .minigame:
                minigameView
            case .roomSelection:
                roomBoardView
            case .notebook:
                notebookBoardView
            case .voting:
                votingBoardView
            case .victory:
                victoryView
            case .defeat:
                defeatView
            case .blackoutReveal:
                blackoutRevealView
            case .blackoutTask:
                blackoutTaskView
            case .notEnoughPlayers:
                notEnoughPlayersView
            }
        }
        .focusScope(defaultFocusNamespace)
    }

    /// Reachable from every connected phase, not just the lobby — the TV is
    /// the shared board, so this is the only way to bail out of a stuck or
    /// unwanted game without force-quitting the app. Sits top-leading so it
    /// never collides with `lobbyView`'s own top-trailing rules/settings
    /// cluster.
    ///
    /// Deliberately `.buttonStyle(.plain)`, not `.card` — on this SDK,
    /// `.card` left the tvOS focus engine completely unable to move focus
    /// off this button in any direction once it landed here (every other
    /// on-screen control became unreachable). `.plain` plus an explicit
    /// circular background gives the same contained look without that
    /// engine bug.
    @ViewBuilder
    private var quitToHomeButton: some View {
        Button {
            showQuitConfirmation = true
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.35), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Quit game")
        .padding(24)
    }

    private var quitConfirmationDialog: some View {
        Color.clear
            .confirmationDialog(
                "End this game?",
                isPresented: $showQuitConfirmation,
                titleVisibility: .visible
            ) {
                Button("End Game for Everyone", role: .destructive) {
                    host.stop()
                    isAtHome = true
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This ends the game for every connected phone, not just this TV.")
            }
    }

    private var homeScreen: some View {
        ZStack {
            // Cinematic looping backdrop, silent and chrome-free — see
            // `LoopingVideoBackground`. Falls back to a plain dark gradient
            // if `intro.mp4` isn't bundled (same fallback contract as
            // `introVideoView`).
            if Bundle.main.url(forResource: "intro2", withExtension: "mp4") != nil {
                LoopingVideoBackground("intro2")
                    .ignoresSafeArea()
            } else {
                LinearGradient(colors: [.black, .phoenixCard], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            }

            // Darkening scrim so the title/buttons stay legible over the
            // video — sits above the video, below every other layer here.
            LinearGradient(
                colors: [.black.opacity(0.25), .black.opacity(0.50)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Rectangle().fill(Color.phoenixGold.opacity(0.5)).frame(width: 40, height: 1.5)
                        Text("· PHOENIX ACADEMY ·")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .tracking(4)
                            .foregroundStyle(Color.phoenixMuted)
                        Rectangle().fill(Color.phoenixGold.opacity(0.5)).frame(width: 40, height: 1.5)
                    }

                    Text("CRACK THE CASE")
                        .font(.system(size: 80, weight: .black, design: .monospaced))
                        .foregroundStyle(.phoenixGold)
                        .shadow(color: .phoenixGold.opacity(0.3), radius: 20, y: 10)
                }

                HStack(spacing: 60) {
                    homeActionButton(title: "NEW GAME", icon: "folder.badge.plus") {
                        // `startNewGame()` swaps in a fresh `GameSession`
                        // (new random join code, empty roster, `.lobby`
                        // phase) in place — reusing the old one after "End
                        // Game" left the join code, roster, and phase all
                        // stale, so reconnecting phones landed in a dead
                        // lobby instead of a real new game. Deliberately
                        // *not* a whole new `HostConnectivityService`: that
                        // would also mint a new `MCPeerID`, and since every
                        // host advertises under the same display name, a
                        // phone that already saw the previous game's host
                        // would dedupe the new peer away (or invite the now-
                        // dead one) and get stuck on "Connecting…" — see
                        // `startNewGame()`'s doc comment. `gameContent`'s own
                        // `onAppear` calls `host.start()` to resume
                        // advertising under the same stable peer identity.
                        host.startNewGame()
                        isAtHome = false
                    }

                    homeActionButton(title: "SETTINGS", icon: "gearshape.fill") {
                        showSettings = true
                    }
                }
            }

        }
    }

    /// A single shared style for both home-screen actions — previously "NEW
    /// GAME" was solid gold and "SETTINGS" was a bordered dark card, an
    /// inconsistency with no meaning behind it. Both now read as identical
    /// dossier tabs, distinguished only by icon/label. `.buttonStyle(.plain)`
    /// is deliberate, not incidental — see `PhoenixTVButtonStyle`'s doc
    /// comment on the tvOS focus engine's trouble with non-`.plain` styles.
    private func homeActionButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        HomeActionButtonView(title: title, icon: icon, action: action)
    }

    private struct HomeActionButtonView: View {
        let title: String
        let icon: String
        let action: () -> Void
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            Button(action: action) {
                Label(title, systemImage: icon)
                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(isFocused ? Color.white : Color.phoenixGold)
                    .padding(.horizontal, 52)
                    .padding(.vertical, 22)
                    .background(Color.phoenixCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(isFocused ? Color.phoenixGold : Color.phoenixGold.opacity(0.55), lineWidth: isFocused ? 3 : 2)
                    )
                    .scaleEffect(isFocused ? 1.05 : 1.0)
                    .animation(.easeOut(duration: 0.2), value: isFocused)
            }
            .buttonStyle(.plain)
            #if os(tvOS)
            .focusEffectDisabled()
            #endif
        }
    }

    private var background: some View {
        CinematicBackground()
    }

    private var lobbyView: some View {
        ZStack {
            VStack(spacing: 36) {
                header

                if host.session.players.isEmpty {
                    emptyState
                } else {
                    playerGrid
                }

                if let countdown {
                    countdownBadge(countdown)
                }
            }
            .padding(60)

            // Positioned via nested Spacers, not `.overlay(alignment:)` —
            // see `gameContent`'s matching comment: on this SDK, an
            // `.overlay`-positioned button cluster left the tvOS focus
            // engine unable to move focus off whichever button had it.
            VStack {
                HStack {
                    Spacer()
                    lobbyChromeButtons
                }
                Spacer()
            }
            .padding(24)
        }
        // On-demand rules review — automatic once per Apple TV via
        // `introVideoView`/`rulesView`, but never reachable again after
        // that first game. This lets anyone check the rules whenever, from
        // the lobby, without waiting for a fresh install.
        .sheet(isPresented: $showRules) {
            ZStack {
                background
                rulesView
            }
        }
    }

    private var lobbyChromeButtons: some View {
        HStack(spacing: 40) {
            Button {
                showRules = true
            } label: {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.phoenixGold)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.5), in: Circle())
                    .overlay(Circle().strokeBorder(Color.phoenixGold.opacity(0.4), lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Rules")

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.phoenixGold)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.5), in: Circle())
                    .overlay(Circle().strokeBorder(Color.phoenixGold.opacity(0.4), lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
    }

    private var header: some View {
        VStack(spacing: 20) {
            Label("ACTIVE CASE FILE", systemImage: "folder.fill")
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .tracking(3)
                .foregroundStyle(Color.phoenixMuted)
                // Clears `quitToHomeButton`/`lobbyChromeButtons`, both
                // pinned at `.padding(24)` with a 44pt circle (occupying
                // roughly y:24-68) — without this the header's first line
                // starts almost flush against them.
                .padding(.top, 28)

            Label("CRACK THE CASE", systemImage: "magnifyingglass")
                .font(.system(size: 80, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(colors: [.phoenixGold, .orange], startPoint: .top, endPoint: .bottom)
                )
                .shadow(color: .phoenixGold.opacity(0.4), radius: 15)

            Text(
                host.session.players.isEmpty
                    ? "Awaiting Detectives..."
                    : "Press Ready on your phone to start the investigation"
            )
            .font(.system(size: 30, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.85))

            if !host.session.players.isEmpty {
                Text("\(readyPlayerCount)/\(host.session.players.count) ready")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.phoenixMuted)
            }

            joinCodeBadge
        }
    }

    private var readyPlayerCount: Int {
        host.session.players.count { $0.isReady }
    }

    /// A large, high-contrast digit-by-digit display of the join code — big
    /// enough to read clearly from across the room on a TV, unlike a small
    /// inline text badge.
    private var joinCodeBadge: some View {
        VStack(spacing: 16) {
            Label("ACCESS CODE", systemImage: "lock.shield.fill")
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .tracking(4)

            HStack(spacing: 20) {
                ForEach(Array(host.session.joinCode.enumerated()), id: \.offset) { _, digit in
                    Text(String(digit))
                        .font(.system(size: 86, weight: .black, design: .rounded))
                        .foregroundStyle(.phoenixGold)
                        .frame(width: 96, height: 120)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .strokeBorder(LinearGradient(colors: [.white.opacity(0.5), .clear], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2)
                        )
                        .shadow(color: .black.opacity(0.5), radius: 15, x: 0, y: 10)
                }
            }
        }
        .padding(.top, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 72))
                .foregroundStyle(.white)
            Text("AWAITING AGENTS…")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .tracking(3)
                .foregroundStyle(Color.phoenixMuted)
            Text("Connect from the phone app to join the case")
                .font(.system(size: 22, design: .rounded))
                .foregroundStyle(Color.phoenixMuted)
        }
        .padding(40)
        .overlay(CornerBrackets(color: .white.opacity(0.25), length: 22, thickness: 2, inset: 4))
    }

    private var playerGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 28), count: 4), spacing: 28) {
            ForEach(host.session.players) { player in
                PlayerBadge(player: player)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 40)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: host.session.players)
    }

    private func countdownBadge(_ value: Int) -> some View {
        Text("\(value)")
            .font(.system(size: 64, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 120, height: 120)
            .background(Color.phoenixGold, in: Circle())
            .shadow(color: Color.phoenixGold.opacity(0.5), radius: 20)
    }

    private var startingView: some View {
        VStack(spacing: 24) {
            Image(systemName: "flashlight.on.fill")
                .font(.system(size: 80))
                .foregroundStyle(Color.phoenixGold)
            Text("The case is about to begin…")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    /// Plays `intro.mp4` from the tvOS target's bundle if one has been added;
    /// otherwise falls back to a text placeholder. Either way, a manual
    /// "Skip" button is always available.
    private var introVideoView: some View {
        ZStack(alignment: .bottomTrailing) {
            if let url = Bundle.main.url(forResource: "intro", withExtension: "mp4") {
                AutoplayingVideoView(url: url) {
                    advanceFromIntroVideo()
                }
            } else {
                placeholderStoryView
            }

            Button(action: advanceFromIntroVideo) {
                Label("Skip", systemImage: "forward.fill")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
            }
            .buttonStyle(PhoenixTVButtonStyle(tint: .black.opacity(0.45)))
            .padding(40)
        }
    }

    private func advanceFromIntroVideo() {
        hasSeenOnboarding = true
        host.beginRules()
    }

    private var preIntroVideoView: some View {
        ZStack(alignment: .bottomTrailing) {
            if let url = Bundle.main.url(forResource: "video_pre_intro", withExtension: "mp4") {
                AutoplayingVideoView(url: url) {
                    withAnimation { isPlayingPreIntro = false }
                }
            } else {
                Color.black.ignoresSafeArea()
                    .onAppear {
                        withAnimation { isPlayingPreIntro = false }
                    }
            }

            Button(action: { withAnimation { isPlayingPreIntro = false } }) {
                Label("Skip", systemImage: "forward.fill")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
            }
            .buttonStyle(PhoenixTVButtonStyle(tint: .black.opacity(0.45)))
            .padding(40)
        }
    }

    private var placeholderStoryView: some View {
        ZStack {
            background

            VStack(spacing: 28) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.phoenixGold)
                Text("Phoenix Academy, 11:47 PM.")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(
                    "The lights just went out… but someone, in the shadows, is still looking " +
                    "for something. Tomorrow morning, the headmaster will find his office a mess. " +
                    "Who did it — and what were they really looking for?"
                )
                .font(.system(size: 22, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 100)
                Text("It's your turn, young detectives.")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.phoenixGold)
            }
            .padding(60)
        }
    }

    private var rulesView: some View {
        VStack(spacing: 22) {
            Label("THE RULES", systemImage: "book.closed.fill")
                .font(.system(size: 38, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.phoenixGold)

            VStack(alignment: .leading, spacing: 14) {
                RuleRow(
                    icon: "hare.fill",
                    text: "Each round, a quick phone challenge decides the turn order. " +
                        "Whoever finishes last risks missing a clue!"
                )
                RuleRow(
                    icon: "door.left.hand.open",
                    text: "Taking turns, each detective explores one of Phoenix Academy's 9 rooms. " +
                        "Only 3 hide a clue."
                )
                RuleRow(
                    icon: "book.fill",
                    text: "Use your notebook to track what you've found and rule out suspects."
                )
                RuleRow(
                    icon: "bolt.slash.fill",
                    text: "Once during the night the storm cuts the power — a Black-out. " +
                        "Everyone must work together on one emergency task before the lights return."
                )
                RuleRow(
                    icon: "hand.point.up.left.fill",
                    text: "When you think you know who did it, press Vote… but be careful — " +
                        "a wrong guess costs your team 5 precious minutes!"
                )
                RuleRow(
                    icon: "timer",
                    text: "You have 30 minutes before the Ambassador arrives. The clock never stops."
                )
            }
            .frame(maxWidth: 720)

            Button {
                if host.session.phase == .rules {
                    // Real first-game onboarding: dismiss straight into the
                    // minigame.
                    hasSeenOnboarding = true
                    host.beginMinigame()
                } else {
                    // On-demand review from the lobby (see `showRules`) —
                    // just close the sheet, nothing about the game itself
                    // should change.
                    showRules = false
                }
            } label: {
                Label(
                    host.session.phase == .rules ? "Got it, let's start!" : "Close",
                    systemImage: "checkmark.circle.fill"
                )
                .font(.system(size: 22, weight: .bold, design: .rounded))
            }
            .buttonStyle(PhoenixTVButtonStyle(tint: .phoenixGreen))
        }
        .padding(60)
    }

    /// Ticks a 3-2-1 countdown, bailing out if a player un-readies mid-count,
    /// then asks the host to transition the lobby into `.starting`.
    private func startCountdown() {
        countdown = Self.countdownSeconds
        Task {
            while let current = countdown, current > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard host.session.canStart else { return }
                countdown = current - 1
            }
            if host.session.canStart {
                host.requestStartGame()
            }
        }
    }

    private var minigameView: some View {
        VStack(spacing: 32) {
            VStack(spacing: 8) {
                Label("WHO WILL BE FASTEST?", systemImage: "magnifyingglass")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.phoenixGold)

                Text(minigameStatusText)
                    .font(.system(size: 24, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))

                // Once the first detective finishes, a shared skip-grace-
                // period countdown starts — anyone still stuck when it hits
                // zero is auto-skipped by the host so the round can't stall
                // forever on one player (see `GameSession.minigameSkipGracePeriod`).
                if let firstFinishAt = host.session.minigameFirstFinishAt, !host.session.allPlayersFinishedMinigame {
                    SkipDeadlineCountdown(
                        deadline: firstFinishAt.addingTimeInterval(GameSession.minigameSkipGracePeriod)
                    )
                }
            }

            if finishedPlayers.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "stopwatch.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(Color.caseWhite)
                    Text("The detectives are playing on their phones…")
                        .font(.system(size: 22, design: .rounded))
                        .foregroundStyle(Color.phoenixMuted)
                }
                .padding(40)
            } else {
                VStack(spacing: 14) {
                    ForEach(Array(finishedPlayers.enumerated()), id: \.element.id) { index, player in
                        LeaderboardRow(
                            rank: index + 1,
                            player: player,
                            isPenalized: host.session.penalizedPlayerIDs.contains(player.id)
                        )
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: 640)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: host.session.minigameFinishOrder)
            }

            if host.session.allPlayersFinishedMinigame {
                Text("Coming up next: the rooms!")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.phoenixGold)
            }
        }
        .padding(60)
    }

    private var finishedPlayers: [Player] {
        host.session.minigameFinishOrder.compactMap { id in
            host.session.players.first { $0.id == id }
        }
    }

    private var minigameStatusText: String {
        let remaining = host.session.players.count - host.session.minigameFinishOrder.count
        if remaining <= 0 {
            return "Everyone's ready!"
        }
        return remaining == 1 ? "Waiting for 1 more player…" : "Waiting for \(remaining) more players…"
    }

    private var roomBoardView: some View {
        VStack(spacing: 36) {
            VStack(spacing: 12) {
                Label("INVESTIGATION AREAS", systemImage: "door.left.hand.open")
                    .font(.system(size: 46, weight: .black, design: .rounded))
                    .foregroundStyle(Color.phoenixGold)
                    .shadow(color: .phoenixGold.opacity(0.3), radius: 10)

                Text("ROUND \(host.session.roundNumber)")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.phoenixMuted)
                    .tracking(2)

                Text(roomSelectionStatusText)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                if !host.session.isRoomSelectionComplete {
                    Text("Only 3 of the 9 rooms hide a clue")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.phoenixMuted)
                }
            }

            if host.session.isRoomSelectionComplete {
                roundSummary
            } else {
                roomGrid
            }
        }
        .padding(50)
    }

    private var roomGrid: some View {
        // Sized to read as a genuine board on a TV screen without spilling
        // past the safe area — 1500 was too aggressive and pushed both the
        // grid and its room-name labels right to (or past) the screen edge.
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 22), count: 3), spacing: 22) {
            ForEach(RoomID.allCases) { room in
                RoomTile(room: room, occupant: occupant(of: room))
            }
        }
        .frame(maxWidth: 1100)
    }

    private var roundSummary: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                ForEach(Array(host.session.roomVisitLog.enumerated()), id: \.offset) { index, visit in
                    RoundSummaryRow(order: index + 1, visit: visit, player: player(for: visit.playerID))
                }
            }
            .frame(maxWidth: 640)

            // Opens automatically (see the isRoomSelectionComplete
            // onChange) — this just tells everyone it's about to happen.
            Label("Read your clue on your phone!", systemImage: "book.fill")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.phoenixGold)
        }
    }

    /// Which player is currently shown standing in `room`, scanning the
    /// whole visit log rather than just the live turn holder — turns advance
    /// as fast as players pick, so the board fills in with everyone who's
    /// already gone this round, not just whoever's turn it is right now.
    private func occupant(of room: RoomID) -> Player? {
        guard let visit = host.session.roomVisitLog.last(where: { $0.roomID == room }) else { return nil }
        return player(for: visit.playerID)
    }

    private func player(for id: UUID) -> Player? {
        host.session.players.first { $0.id == id }
    }

    /// The local win leaderboard, resolved against currently-connected
    /// players' nicknames (a stored win can't display a name for someone
    /// no longer connected, so it's silently skipped).
    private var leaderboardEntries: [(name: String, wins: Int)] {
        gameStats.leaderboard { id in player(for: id)?.nickname }
    }

    private var roomSelectionStatusText: String {
        if host.session.isRoomSelectionComplete {
            return "Round complete!"
        }
        guard let currentID = host.session.currentTurnPlayerID, let player = player(for: currentID) else {
            return ""
        }
        return "\(player.nickname)'s turn"
    }

    private var notebookBoardView: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text("SUSPECT DATABASE")
                    .font(.system(size: 34, weight: .black, design: .monospaced))
                    .foregroundStyle(Color.phoenixGold)
                    .tracking(4)

                Text("ROUND \(host.session.roundNumber)")
                    .font(.system(size: 18, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Color.phoenixMuted)
                    .tracking(2)
            }

            if let accusation = host.session.lastAccusation, !accusation.wasCorrect {
                wrongAccusationBanner(accusation)
            }

            if !host.session.failedAccusationPlayerIDs.isEmpty {
                Label(
                    "\(host.session.failedAccusationPlayerIDs.count) failed accusation\(host.session.failedAccusationPlayerIDs.count == 1 ? "" : "s") this round",
                    systemImage: "xmark.seal.fill"
                )
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.phoenixMuted)
            }

            if host.session.isCurrentRoundBlackout {
                Text("VOTING OFFLINE - BLACKOUT")
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.phoenixDestructive)
                    .tracking(2)
                    .padding()
            }

            // Sized to fill most of the board — this single image is the
            // group photo of all 6 suspects, so it needs to read large
            // enough on a TV screen for their individual details (not just
            // a thumbnail) to actually be visible from across the room.
            Image("ImageDatabase")
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 760)
                .overlay(CCTVScanlines())
                .overlay(
                    CornerBrackets(
                        color: Color.phoenixGold.opacity(0.8),
                        length: 30,
                        thickness: 3,
                        inset: 4
                    )
                )
                .overlay(Rectangle().strokeBorder(Color.phoenixGold.opacity(0.4), lineWidth: 2))
                .shadow(color: .black.opacity(0.4), radius: 10, x: 0, y: 10)
                .padding(.horizontal, 20)

            NotebookCountdownView {
                guard host.session.phase == .notebook else { return }
                host.beginNextRound()
            }
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 24)
    }

    /// Auto-advances the board out of `.notebook` after a countdown — but
    /// only while `.notebook` is actually on screen. `.onDisappear` stops
    /// the timer the moment the phase moves away (most commonly to
    /// `.voting`), instead of leaving it running unseen in the background:
    /// without that cleanup, `Timer.scheduledTimer` isn't tied to this
    /// view's lifetime at all, so a leaked timer from a previous mount kept
    /// ticking through the vote and could fire `beginNextRound()` at an
    /// arbitrary moment after voting returned to `.notebook`, cutting the
    /// freshly-restarted countdown short. Since SwiftUI gives this view a
    /// brand-new identity (and thus a fresh `secondsRemaining`) every time
    /// `.notebook` comes back on screen, simply stopping the old timer on
    /// disappear is enough to both "pause" while voting and restart at 10s
    /// once back — no extra state needed.
    private struct NotebookCountdownView: View {
        let onComplete: () -> Void
        @State private var secondsRemaining = 10
        @State private var timer: Timer?

        var body: some View {
            VStack(spacing: 8) {
                Text("NEXT ROUND INITIATING AUTOMATICALLY IN")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))

                Text("\(secondsRemaining)")
                    .font(.system(size: 32, weight: .black, design: .monospaced))
                    .foregroundStyle(Color.phoenixGold)
            }
            .padding(.top, 20)
            .onAppear {
                startCountdown()
            }
            .onDisappear {
                timer?.invalidate()
            }
        }

        private func startCountdown() {
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
                if secondsRemaining > 0 {
                    secondsRemaining -= 1
                } else {
                    timer.invalidate()
                    onComplete()
                }
            }
        }
    }

    /// Shown on the shared board after a failed accusation — names the
    /// accuser but deliberately never the suspect they picked, so the rest
    /// of the table doesn't get a free hint about who's already been ruled
    /// out by someone else's guess.
    private func wrongAccusationBanner(_ accusation: Accusation) -> some View {
        let accuserName = player(for: accusation.playerID)?.nickname ?? "AGENT"
        return Text("\(accuserName.uppercased()) GUESSED WRONG.")
            .font(.system(size: 24, weight: .bold, design: .monospaced))
            .foregroundStyle(Color.phoenixDestructive)
            .padding()
            .background(Color.phoenixDestructive.opacity(0.1))
            .overlay(Rectangle().strokeBorder(Color.phoenixDestructive, lineWidth: 2))
    }

    private func suspect(for id: String) -> Suspect? {
        Suspects.all.first { $0.id == id }
    }

    private var votingBoardView: some View {
        VStack(spacing: 28) {
            Image(systemName: "magnifyingglass.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(Color.phoenixGold)
                .symbolEffect(.pulse)

            Text(votingStatusText)
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text("Every other phone is locked…")
                .font(.system(size: 22, design: .rounded))
                .foregroundStyle(Color.phoenixMuted)
        }
        .padding(60)
    }

    private var votingStatusText: String {
        guard let votingPlayerID = host.session.votingPlayerID, let player = player(for: votingPlayerID) else {
            return "Someone is voting…"
        }
        return "\(player.nickname) is voting…"
    }

    /// Wrapped in a `ScrollView` (unlike most other board screens, which fit
    /// comfortably in a plain `VStack`) as a defensive measure: with a long
    /// leaderboard or extra-wide text wrapping, the content here could in
    /// principle exceed the screen height, and tvOS's focus engine can only
    /// navigate to elements that are actually on screen — a "Play Again"
    /// pushed below the fold would be unreachable no matter what. A
    /// `ScrollView` guarantees that can never happen; tvOS auto-scrolls the
    /// focused element into view natively, no extra code needed.
    private var victoryView: some View {
        ScrollView {
            VStack(spacing: 28) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 88))
                    .foregroundStyle(Color.phoenixGold)

                Text("CASE SOLVED!")
                    .font(.system(size: 52, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)

                if let accusation = host.session.lastAccusation, let winner = player(for: accusation.playerID) {
                    Text("\(winner.nickname) exposed the culprit and wins the scholarship!")
                        .font(.system(size: 24, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                }

                if let culprit = suspect(for: host.session.culpritID) {
                    VStack(spacing: 10) {
                        SuspectPortraitView(suspect: culprit)
                            .frame(height: 140)
                        Text("The culprit was \(culprit.name)")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.phoenixGold)
                        Text(culprit.role)
                            .font(.system(size: 16, design: .rounded))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .padding(.top, 10)
                }

                if !leaderboardEntries.isEmpty {
                    VStack(spacing: 8) {
                        Label("LEADERBOARD", systemImage: "medal.fill")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))

                        VStack(spacing: 6) {
                            ForEach(Array(leaderboardEntries.enumerated()), id: \.offset) { _, entry in
                                HStack(spacing: 10) {
                                    Text(entry.name)
                                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.white)
                                    Spacer()
                                    Text(entry.wins == 1 ? "1 win" : "\(entry.wins) wins")
                                        .font(.system(size: 15, weight: .medium, design: .rounded))
                                        .foregroundStyle(Color.phoenixGold)
                                }
                                .frame(maxWidth: 260)
                            }
                        }
                    }
                    .padding(.top, 6)
                }

                finalRankingSection

                Button {
                    host.playAgain()
                } label: {
                    Label("Play Again", systemImage: "arrow.counterclockwise.circle.fill")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                }
                .buttonStyle(PhoenixTVButtonStyle(tint: .phoenixGreen))
                .padding(.top, 10)
                // The one thing on this screen that should reliably have
                // focus the instant it appears — see `defaultFocusNamespace`.
                .prefersDefaultFocus(true, in: defaultFocusNamespace)
            }
            .padding(60)
        }
    }

    /// Wrapped in a `ScrollView` for the same reason as `victoryView` — see
    /// its doc comment.
    private var defeatView: some View {
        ScrollView {
            VStack(spacing: 28) {
                Image(systemName: "hourglass.tophalf.fill")
                    .font(.system(size: 88))
                    .foregroundStyle(Color.phoenixDestructive)

                Text("CASE UNSOLVED")
                    .font(.system(size: 52, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)

                Text("\(GameSession.maxRoundNumber) rounds have passed and nobody named the real culprit. Everyone loses.")
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 60)

                if let culprit = suspect(for: host.session.culpritID) {
                    VStack(spacing: 10) {
                        SuspectPortraitView(suspect: culprit)
                            .frame(height: 140)
                        Text("The culprit was \(culprit.name)")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.phoenixGold)
                        Text(culprit.role)
                            .font(.system(size: 16, design: .rounded))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .padding(.top, 10)
                }

                finalRankingSection

                Button {
                    host.playAgain()
                } label: {
                    Label("Play Again", systemImage: "arrow.counterclockwise.circle.fill")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                }
                .buttonStyle(PhoenixTVButtonStyle(tint: .phoenixGreen))
                .padding(.top, 10)
                .prefersDefaultFocus(true, in: defaultFocusNamespace)
            }
            .padding(60)
        }
    }

    /// This game's cumulative minigame ranking (`GameSession.finalRanking`),
    /// shown on both end screens. Reuses `LeaderboardRow` — the same row
    /// style as the per-round leaderboard — so the last-place player gets
    /// the identical red "PENALTY" badge treatment for the game as a
    /// whole, not just for a single round.
    @ViewBuilder
    private var finalRankingSection: some View {
        let ranking = host.session.finalRanking
        if ranking.count > 1 {
            VStack(spacing: 8) {
                Label("FINAL RANKING", systemImage: "list.number")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))

                VStack(spacing: 10) {
                    ForEach(Array(ranking.enumerated()), id: \.element.id) { index, player in
                        LeaderboardRow(
                            rank: index + 1,
                            player: player,
                            isPenalized: player.id == ranking.last?.id
                        )
                    }
                }
                .frame(maxWidth: 640)
            }
            .padding(.top, 6)
        }
    }

    private var notEnoughPlayersView: some View {
        VStack(spacing: 28) {
            Image(systemName: "person.fill.xmark")
                .font(.system(size: 80))
                .foregroundStyle(Color.phoenixDestructive)

            Text("NOT ENOUGH DETECTIVES")
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)

            Text("At least 2 players are needed to keep investigating.")
                .font(.system(size: 22, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))

            Button {
                host.acknowledgeNotEnoughPlayers()
            } label: {
                Label("Back to lobby", systemImage: "house.fill")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
            }
            .buttonStyle(PhoenixTVButtonStyle(tint: .phoenixGreen))
            .padding(.top, 10)
            .prefersDefaultFocus(true, in: defaultFocusNamespace)
        }
        .padding(60)
    }

    private var blackoutRevealView: some View {
        VStack(spacing: 28) {
            Image(systemName: "bolt.slash.fill")
                .font(.system(size: 80))
                .foregroundStyle(Color.phoenixGold)
                .symbolEffect(.pulse)

            Text("BLACK-OUT!")
                .font(.system(size: 52, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)

            Text(
                "The lights at Phoenix Academy suddenly go out… when they come back on, someone has " +
                "moved the clues to different rooms."
            )
            .font(.system(size: 24, design: .rounded))
            .foregroundStyle(.white.opacity(0.85))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 100)
        }
        .padding(60)
    }

    private var blackoutTaskView: some View {
        VStack(spacing: 28) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 72))
                .foregroundStyle(Color.phoenixGold)

            Text("EMERGENCY TASK")
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)

            Text("Every detective must complete the task on their phone!")
                .font(.system(size: 22, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))

            if let startedAt = host.session.blackoutTaskStartedAt {
                TimelineView(.periodic(from: startedAt, by: 1)) { context in
                    Text(elapsedTimeText(since: startedAt, now: context.date))
                        .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.phoenixMuted)
                }

                // Anyone still stuck once the shared skip-grace-period
                // elapses is auto-skipped by the host, with no penalty —
                // see `GameSession.blackoutSkipGracePeriod`.
                if !host.session.allPlayersFinishedBlackoutTask {
                    SkipDeadlineCountdown(
                        deadline: startedAt.addingTimeInterval(GameSession.blackoutSkipGracePeriod)
                    )
                }
            }

            if host.session.blackoutMinigame == .lightRegulator {
                HStack(spacing: 30) {
                    VStack(spacing: 6) {
                        Text("TARGET")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))
                        Text("\(Int(host.session.blackoutLightTarget))%")
                            .font(.system(size: 40, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.phoenixGold)
                    }
                    VStack(spacing: 6) {
                        Text("TEAM AVERAGE")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))
                        Text("\(Int(host.session.blackoutLightAverage))%")
                            .font(.system(size: 40, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.phoenixGreen)
                    }
                }
            } else {
                Text("\(host.session.blackoutTaskFinishedPlayerIDs.count)/\(host.session.players.count) done")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.phoenixGreen)
            }
        }
        .padding(60)
    }

    private func elapsedTimeText(since startedAt: Date, now: Date) -> String {
        let elapsed = max(0, Int(now.timeIntervalSince(startedAt)))
        return String(format: "%02d:%02d", elapsed / 60, elapsed % 60)
    }
}

/// An "agent dossier card" for one connected player — corner brackets frame
/// the whole card like a case-file photo, and the ready state doubles as a
/// stamped status tag (`READY`/`STANDBY`) under the name, on top of the
/// existing gold-ring + seal treatment on the avatar itself.
private struct PlayerBadge: View {
    let player: Player

    var body: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                AvatarBadge(player: player, diameter: 100)
                    .overlay(
                        Circle().strokeBorder(player.isReady ? Color.phoenixGold : .white.opacity(0.15), lineWidth: player.isReady ? 4 : 1)
                    )

                if player.isReady {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.phoenixGold)
                        .background(Circle().fill(.white))
                        .offset(x: 4, y: 4)
                }
            }

            VStack(spacing: 4) {
                Text(player.nickname)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(player.isReady ? "READY" : "STANDBY")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(player.isReady ? Color.phoenixGold : Color.phoenixMuted.opacity(0.7))
            }
        }
        .padding(18)
        .background(Color.phoenixCard, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(player.isReady ? Color.phoenixGold.opacity(0.5) : Color.white.opacity(0.08), lineWidth: player.isReady ? 1.5 : 1)
        )
        .overlay(CornerBrackets(color: .white.opacity(0.2), length: 14, thickness: 1.5, inset: 6))
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 6)
    }
}

/// A compact countdown badge shown on the board once the shared skip-
/// grace-period window has started, mirroring the same deadline shown on
/// each stuck player's phone (see `SkipCountdownBar` in
/// `CrackTheCaseIos/ContentView.swift`). The host is the actual authority on
/// when the deadline expires — this is purely the on-screen readout.
private struct SkipDeadlineCountdown: View {
    let deadline: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(deadline.timeIntervalSince(context.date).rounded(.up)))
            Label("Auto-skip in \(remaining)s", systemImage: "timer")
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .foregroundStyle(remaining <= 5 ? Color.phoenixDestructive : Color.phoenixMuted)
        }
    }
}

private struct LeaderboardRow: View {
    let rank: Int
    let player: Player
    let isPenalized: Bool

    var body: some View {
        HStack(spacing: 20) {
            Text("\(rank)")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(rank == 1 ? Color.phoenixGold : .white.opacity(0.6))
                .frame(width: 44)

            AvatarBadge(player: player, diameter: 56)

            Text(player.nickname)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            Spacer()

            if isPenalized {
                Label("PENALTY", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.phoenixDestructive, in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                    .shadow(color: .phoenixDestructive.opacity(0.5), radius: 8, y: 2)
            }
        }
        .padding(16)
        .background(Color.phoenixCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    rank == 1 ? Color.phoenixGold.opacity(0.6) : Color.white.opacity(0.08),
                    lineWidth: rank == 1 ? 2 : 1
                )
        )
        .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
    }
}

private struct RuleRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(Color.phoenixGold)
                .frame(width: 32)
            Text(text)
                .font(.system(size: 17, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}

/// A single room's tile on the board, styled as a security-camera feed —
/// the room's "CAM 0X — NAME" caption sits above the frame like an on-screen
/// label (unlike a normal photo caption below it), and the frame itself
/// reads as a monitor: squared corners, viewfinder corner brackets, a
/// scanline overlay, a faint night-vision tint, a pulsing REC indicator, and
/// a live ticking timestamp.
private struct RoomTile: View {
    let room: RoomID
    let occupant: Player?

    private var cameraNumber: Int {
        (RoomID.allCases.firstIndex(of: room) ?? 0) + 1
    }

    var body: some View {
        VStack(spacing: 8) {
            Text("CAM \(String(format: "%02d", cameraNumber)) — \(room.displayName.uppercased())")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            ZStack {
                // Falls back to the SF Symbol icon (same treatment as
                // `SuspectPortraitView`) if a cover is ever missing.
                Group {
                    if let uiImage = UIImage(named: room.coverAsset) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .saturation(0.35)
                    } else {
                        Color.black.opacity(0.3)
                            .overlay {
                                Image(systemName: room.icon)
                                    .font(.system(size: 44))
                                    .foregroundStyle(occupant == nil ? .white.opacity(0.8) : .white.opacity(0.25))
                            }
                    }
                }
                .frame(height: 200)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    // Faint night-vision green tint over the (desaturated)
                    // footage, darkened further once someone's inside.
                    Color.green.opacity(0.10)
                    if occupant != nil {
                        Color.black.opacity(0.5)
                    }
                }
                .overlay(CCTVScanlines())
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                if let occupant {
                    AvatarBadge(player: occupant, diameter: 68)
                        .overlay(Circle().strokeBorder(Color.phoenixGold, lineWidth: 3))
                }

                VStack {
                    HStack {
                        recIndicator
                        Spacer()
                    }
                    Spacer()
                    HStack {
                        Spacer()
                        CCTVTimestamp(seed: cameraNumber)
                    }
                }
                .padding(8)
            }
            .frame(height: 200)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        occupant != nil ? Color.phoenixGold.opacity(0.7) : Color.white.opacity(0.15),
                        lineWidth: occupant != nil ? 2 : 1
                    )
            )
            .overlay(
                CornerBrackets(
                    color: occupant != nil ? Color.phoenixGold.opacity(0.8) : .white.opacity(0.35),
                    length: 16,
                    thickness: 2,
                    inset: 3
                )
            )
            .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
        }
        .frame(maxWidth: .infinity)
    }

    private var recIndicator: some View {
        HStack(spacing: 5) {
            Image(systemName: "circle.fill")
                .font(.system(size: 8))
                .foregroundStyle(.red)
                .symbolEffect(.pulse)
            Text("REC")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.black.opacity(0.5), in: Capsule())
    }
}

/// Faint horizontal scanlines drawn across whatever frame it's overlaid on
/// — part of `RoomTile`'s security-camera-feed look.
private struct CCTVScanlines: View {
    var spacing: CGFloat = 4
    var lineOpacity: Double = 0.06

    var body: some View {
        Canvas { context, size in
            var y: CGFloat = 0
            while y < size.height {
                context.fill(
                    Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                    with: .color(.white.opacity(lineOpacity))
                )
                y += spacing
            }
        }
        .allowsHitTesting(false)
    }
}

/// A live, ticking "HH:mm:ss" readout in the corner of a `RoomTile`, like a
/// real CCTV monitor's on-screen clock — anchored to a fixed evening base
/// time (21:00:00) rather than the device's actual clock. The story takes
/// place at night, so showing the real device time (which could be broad
/// daylight, depending on when someone actually plays) would break that
/// immediately. All 9 tiles share the same base time (a real building's
/// cameras are all synced to one clock), while still ticking forward in
/// real time for the "live feed" effect. `seed` is kept as a parameter for
/// call-site compatibility (`RoomTile` passes `cameraNumber`) but no longer
/// affects the displayed time.
private struct CCTVTimestamp: View {
    let seed: Int

    @State private var startedAt = Date()

    private var baseTime: Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = 21
        components.minute = 0
        components.second = 0
        return Calendar.current.date(from: components) ?? Date()
    }

    /// Fixed 24-hour "HH:mm:ss" formatting regardless of the device's
    /// locale — a surveillance-camera timestamp reading "9:14:02 PM" would
    /// break the illusion.
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = context.date.timeIntervalSince(startedAt)
            Text(Self.formatter.string(from: baseTime.addingTimeInterval(elapsed)))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.phoenixMuted)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.black.opacity(0.5), in: Capsule())
        }
    }
}

private struct RoundSummaryRow: View {
    let order: Int
    let visit: RoomVisit
    let player: Player?

    var body: some View {
        HStack(spacing: 16) {
            Text("\(order)")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 32)

            if let player {
                AvatarBadge(player: player, diameter: 44)
                Text(player.nickname)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }

            Image(systemName: "arrow.right")
                .foregroundStyle(.white.opacity(0.4))

            Label(visit.roomID.displayName, systemImage: visit.roomID.icon)
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))

            Spacer()
        }
        .padding(12)
        .phoenixCardStyle(cornerRadius: 14)
    }
}

/// A vertical (portrait-orientation) picture of a suspect, shown at its own
/// aspect ratio — never cropped — so the whole character is visible. Every
/// suspect display (this view, the notebook grid, the accusation picker)
/// routes through here and shares the same `"<CaseColor>"` asset (e.g.
/// `"Blue"`) also used for player avatar badges, matching `Suspect.name`;
/// there's a single asset per case color, not a separate one per suspect
/// id. Falls back to a soft silhouette placeholder if that asset is ever
/// missing (e.g. a future suspect added without art yet).
struct SuspectPortraitView: View {
    let suspect: Suspect

    private var assetName: String { suspect.name }

    var body: some View {
        Group {
            if let uiImage = UIImage(named: assetName) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                placeholder
                    .aspectRatio(3 / 4, contentMode: .fit)
            }


        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [.phoenixCard, .phoenixGreenDark], startPoint: .top, endPoint: .bottom)
            Image(systemName: suspect.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 48, height: 48)
                .foregroundStyle(.white.opacity(0.35))
        }
    }
}

#Preview {
    ContentView()
}

struct AutoplayingVideoView: View {
    let url: URL
    var loops: Bool = false
    var onVideoEnd: (() -> Void)? = nil
    @State private var player: AVPlayer?

    var body: some View {
        PureAVPlayerView(player: player)
            .allowsHitTesting(false)
            .focusable(false)
            .ignoresSafeArea()
            .onAppear {
                let p = AVPlayer(url: url)
                self.player = p
                p.play()
            }
            .onDisappear {
                player?.pause()
            }
            .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { notification in
                if let item = notification.object as? AVPlayerItem, item == player?.currentItem {
                    if loops {
                        player?.seek(to: .zero)
                        player?.play()
                    } else {
                        onVideoEnd?()
                    }
                }
            }
    }
}

#if os(tvOS) || os(iOS)
struct PureAVPlayerView: UIViewRepresentable {
    let player: AVPlayer?
    
    func makeUIView(context: Context) -> UIView {
        let view = PlayerUIView()
        view.isUserInteractionEnabled = false
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let view = uiView as? PlayerUIView {
            view.playerLayer.player = player
        }
    }
}

class PlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
#endif
