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
    /// Local win-count leaderboard, persisted on this Apple TV across
    /// "Play Again" restarts and app relaunches — see `GameStats.swift`.
    @State private var gameStats = GameStats.load()
    @Environment(\.scenePhase) private var scenePhase
    /// Lets the intro video and rulebook be skipped automatically from the
    /// second game onward, per the design: both are only mandatory the
    /// first time this Apple TV hosts a game.
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    private static let countdownSeconds = 3
    /// How long the board shows "read your clue on your phone!" after the
    /// last player picks their room, before auto-opening the notebook — long
    /// enough for everyone to read their own private reveal, since every
    /// clue lands on every phone at the same moment (see
    /// `HostConnectivityService`'s batched `.chooseRoom` handling).
    private static let clueReadingSeconds = 10

    var body: some View {
        ZStack {
            background

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
            case .blackoutReveal:
                blackoutRevealView
            case .blackoutTask:
                blackoutTaskView
            case .notEnoughPlayers:
                notEnoughPlayersView
            }
        }
        .animation(.easeInOut(duration: 0.3), value: host.session.phase)
        .onAppear {
            host.start()
            #if os(tvOS) || os(iOS)
            UIApplication.shared.isIdleTimerDisabled = true
            #endif
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
                try? await Task.sleep(for: .seconds(Self.clueReadingSeconds))
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

    private var background: some View {
        LinearGradient(
            colors: [.phoenixBackground, .phoenixGreenDark.opacity(0.35), .phoenixBackground],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var lobbyView: some View {
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
        .overlay(alignment: .topTrailing) {
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(18)
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet()
        }
    }

    private var header: some View {
        VStack(spacing: 20) {
            Label("PHOENIX ACADEMY", systemImage: "magnifyingglass")
                .font(.system(size: 64, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.phoenixGold)

            Text(
                host.session.players.isEmpty
                    ? "Waiting for young detectives…"
                    : "Press Ready on your phone to start the investigation"
            )
            .font(.system(size: 28, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.85))

            joinCodeBadge
        }
    }

    /// A large, high-contrast digit-by-digit display of the join code — big
    /// enough to read clearly from across the room on a TV, unlike a small
    /// inline text badge.
    private var joinCodeBadge: some View {
        VStack(spacing: 14) {
            Label("JOIN CODE", systemImage: "lock.shield.fill")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.65))
                .tracking(3)

            HStack(spacing: 18) {
                ForEach(Array(host.session.joinCode.enumerated()), id: \.offset) { _, digit in
                    Text(String(digit))
                        .font(.system(size: 76, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 86, height: 108)
                        .background(Color.phoenixCard, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(Color.phoenixGold, lineWidth: 3)
                        )
                        .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 8)
                }
            }
        }
        .padding(.top, 6)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 72))
                .foregroundStyle(Color.phoenixGreen)
            Text("Connect from the phone app to join the case")
                .font(.system(size: 22, design: .rounded))
                .foregroundStyle(Color.phoenixMuted)
        }
        .padding(40)
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
                VideoPlayer(player: AVPlayer(url: url))
                    .ignoresSafeArea()
                    .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { _ in
                        advanceFromIntroVideo()
                    }
            } else {
                placeholderStoryView
            }

            Button(action: advanceFromIntroVideo) {
                Label("Skip", systemImage: "forward.fill")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
            }
            .buttonStyle(.bordered)
            .tint(.white)
            .padding(40)
        }
    }

    private func advanceFromIntroVideo() {
        hasSeenOnboarding = true
        host.beginRules()
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
        VStack(spacing: 28) {
            Label("THE RULES", systemImage: "book.closed.fill")
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.phoenixGold)

            VStack(alignment: .leading, spacing: 18) {
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
                    icon: "hand.point.up.left.fill",
                    text: "When you think you know who did it, press Vote… but be careful not to get it wrong!"
                )
            }
            .frame(maxWidth: 720)

            Button {
                hasSeenOnboarding = true
                host.beginMinigame()
            } label: {
                Label("Got it, let's start!", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .padding(.horizontal, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.phoenixGreen)
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
                Label("WHO WILL BE FASTEST?", systemImage: "hare.fill")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.phoenixGold)

                Text(minigameStatusText)
                    .font(.system(size: 24, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
            }

            if finishedPlayers.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "stopwatch.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(Color.phoenixGreen)
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
                            isPenalized: player.id == host.session.penalizedPlayerID
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
        VStack(spacing: 32) {
            VStack(spacing: 8) {
                Label("THE ROOMS OF PHOENIX ACADEMY", systemImage: "door.left.hand.open")
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.phoenixGold)

                Text("Round \(host.session.roundNumber)")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))

                Text(roomSelectionStatusText)
                    .font(.system(size: 24, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
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
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: 3), spacing: 20) {
            ForEach(RoomID.allCases) { room in
                RoomTile(room: room, occupant: occupant(of: room))
            }
        }
        .frame(maxWidth: 760)
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
        VStack(spacing: 32) {
            VStack(spacing: 8) {
                Label("WHO DID IT?", systemImage: "book.fill")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.phoenixGold)

                Text("Round \(host.session.roundNumber)")
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
            }

            if let accusation = host.session.lastAccusation, !accusation.wasCorrect {
                wrongAccusationBanner(accusation)
            }

            if host.session.isCurrentRoundBlackout {
                Label("Black-out round: no votes this time!", systemImage: "bolt.slash.fill")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.phoenixGold)
                    .padding(14)
                    .phoenixCardStyle(cornerRadius: 14)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: 3), spacing: 20) {
                ForEach(Suspects.all) { suspect in
                    SuspectCard(suspect: suspect)
                }
            }
            .frame(maxWidth: 900)

            Button {
                host.beginNextRound()
            } label: {
                Label("Next round", systemImage: "arrow.clockwise.circle.fill")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .padding(.horizontal, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.phoenixGreen)
        }
        .padding(50)
    }

    private func wrongAccusationBanner(_ accusation: Accusation) -> some View {
        let accuserName = player(for: accusation.playerID)?.nickname ?? "A player"
        let suspectName = suspect(for: accusation.suspectID)?.name ?? "someone"
        return Label("\(accuserName) accused \(suspectName) — wrong! The game continues.", systemImage: "xmark.circle.fill")
            .font(.system(size: 20, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.phoenixDestructive)
            .padding(16)
            .phoenixCardStyle(cornerRadius: 16)
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

    private var victoryView: some View {
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

            Button {
                host.playAgain()
            } label: {
                Label("Play Again", systemImage: "arrow.counterclockwise.circle.fill")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .padding(.horizontal, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.phoenixGreen)
            .padding(.top, 10)
        }
        .padding(60)
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
                    .padding(.horizontal, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.phoenixGreen)
            .padding(.top, 10)
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

private struct PlayerBadge: View {
    let player: Player

    var body: some View {
        VStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                AvatarBadge(player: player, diameter: 110)
                    .overlay(
                        Circle().strokeBorder(player.isReady ? Color.phoenixGold : .white.opacity(0.15), lineWidth: player.isReady ? 4 : 1)
                    )

                if player.isReady {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Color.phoenixGold)
                        .background(Circle().fill(.white))
                        .offset(x: 4, y: 4)
                }
            }

            Text(player.nickname)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(16)
        .background(Color.phoenixCard, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 6)
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
                Label("Clue hidden", systemImage: "eye.slash.fill")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.phoenixDestructive)
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
                .font(.system(size: 26))
                .foregroundStyle(Color.phoenixGold)
                .frame(width: 36)
            Text(text)
                .font(.system(size: 20, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}

private struct RoomTile: View {
    let room: RoomID
    let occupant: Player?

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Image(systemName: room.icon)
                    .font(.system(size: 32))
                    .foregroundStyle(occupant == nil ? .white.opacity(0.8) : .white.opacity(0.25))

                if let occupant {
                    AvatarBadge(player: occupant, diameter: 56)
                        .overlay(Circle().strokeBorder(Color.phoenixGold, lineWidth: 3))
                }
            }
            .frame(height: 64)

            Text(room.displayName)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(Color.phoenixCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    occupant != nil ? Color.phoenixGold.opacity(0.6) : Color.white.opacity(0.08),
                    lineWidth: occupant != nil ? 2 : 1
                )
        )
        .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
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

private struct SuspectCard: View {
    let suspect: Suspect

    var body: some View {
        VStack(spacing: 12) {
            SuspectPortraitView(suspect: suspect)
                .frame(height: 150)

            Text(suspect.name)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(suspect.role)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.phoenixGold)

            Text(suspect.detail)
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 6) {
                CaseColorTag(color: suspect.color)
                EvidenceTraitList(suspect: suspect, spacing: 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .phoenixCardStyle()
    }
}

/// A vertical (portrait-orientation) picture of a suspect. Real art should
/// be added to the asset catalog as `"suspect-<id>"` (e.g.
/// `"suspect-headmaster"`, matching `Suspect.id`) — until then this shows a
/// soft silhouette placeholder instead of a flat color block.
struct SuspectPortraitView: View {
    let suspect: Suspect

    private var assetName: String { "suspect-\(suspect.id)" }

    var body: some View {
        ZStack {
            if let uiImage = UIImage(named: assetName) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholder
            }
        }
        .aspectRatio(3 / 4, contentMode: .fit)
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
