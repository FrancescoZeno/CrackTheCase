//
//  ContentView.swift
//  CrackTheCaseIos
//
//  Created by AFP PAR 049 on 01/07/2026.
//

import SwiftUI
import MultipeerConnectivity
import CrackTheCaseCore

/// The controller screen shown on a player's iPhone: find the Apple TV host,
/// connect, pick nickname/avatar, and toggle "Ready".
struct ContentView: View {
    @State private var client = ClientConnectivityService()
    @State private var nickname = PlayerNickname.saved() ?? ""
    @AppStorage("savedAvatarID") private var savedAvatarID: String = ""
    @State private var codeInput = ""
    @State private var roomFindingSecondsRemaining: Int?
    /// Tracks the in-flight countdown Task below so a new `onChange` firing
    /// mid-countdown cancels the stale one instead of letting two loops race
    /// and clobber `roomFindingSecondsRemaining`.
    @State private var roomFindingCountdownTask: Task<Void, Never>?
    @State private var reconnectAttempts = 0
    /// Suspects this player has ruled out — purely a personal aid, never
    /// sent to the host.
    @State private var excludedSuspectIDs: Set<String> = []
    @State private var accusationCandidate: Suspect?
    /// The suspect currently shown full-screen (portrait + details), if any.
    @State private var suspectDetail: Suspect?
    @State private var showSettings = false
    @AppStorage(GameSettings.hapticsEnabledKey) private var hapticsEnabled = true
    /// Tracks the in-flight Black-out vibration loop so a phase change can
    /// stop it (see the `client.phase` `onChange` below).
    @State private var blackoutPulseTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase

    /// Caps automatic reconnect attempts so a connection that keeps failing
    /// shows a manual "Retry" button instead of retrying silently forever.
    private static let maxAutoReconnectAttempts = 4
    private static let roomReadingSeconds = 10

    private var selectedAvatar: Avatar? {
        Avatar(rawValue: savedAvatarID)
    }

    private var myPlayer: Player? {
        client.players.first { $0.id == client.localPlayerID }
    }

    private var isReady: Bool { myPlayer?.isReady ?? false }

    var body: some View {
        NavigationStack {
            ZStack {
                background
                content
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSettings) {
                SettingsSheet()
            }
        }
        .tint(.phoenixGold)
        .onAppear { client.startBrowsing() }
        .onChange(of: client.discoveredHosts) { _, hosts in
            // The common case is a single Apple TV in the room: connect
            // straight away instead of making a family stop and pick from a
            // list. If more than one host turns up (a second TV, or a stale
            // instance left over from testing), fall back to letting the
            // player choose.
            guard client.connectionState == .browsing, hosts.count == 1, let onlyHost = hosts.first else { return }
            client.connect(to: onlyHost)
        }
        .onChange(of: scenePhase) { _, phase in
            // Coming back to the foreground (e.g. after the screen locked)
            // is one of the most common ways this connection actually drops
            // — make sure we start looking for the host again instead of
            // sitting on a stale "searching…" screen that isn't searching.
            // A fresh foreground event earns a fresh set of retries.
            guard phase == .active else { return }
            switch client.connectionState {
            case .idle, .disconnected:
                reconnectAttempts = 0
                client.startBrowsing()
            case .browsing, .connecting, .connected:
                break
            }
        }
        .onChange(of: client.connectionState) { _, state in
            switch state {
            case .connected:
                reconnectAttempts = 0
            case .disconnected:
                // The connection dropped for any reason (Wi-Fi hiccup, the
                // host briefly backgrounding, walking out of range) — retry
                // on our own instead of waiting for the player to relaunch.
                retryConnection()
            case .connecting:
                // Safety net for a silently-stuck invite (comfortably under
                // MCNearbyServiceBrowser's own 30s invite timeout).
                Task {
                    try? await Task.sleep(for: .seconds(12))
                    guard client.connectionState == .connecting else { return }
                    retryConnection()
                }
            case .idle, .browsing:
                break
            }
        }
        .onChange(of: client.joinAuthorization) { _, authorization in
            // If the host's joinResult is lost in transit, don't leave the
            // "Join" button spinning forever — time out and let the player
            // retry.
            guard authorization == .pending else { return }
            Task {
                try? await Task.sleep(for: .seconds(6))
                client.timeoutJoinRequest()
            }
        }
        .onChange(of: client.joinAuthorization) { _, authorization in
            // The moment the code is accepted, join with the nickname
            // already entered above it on the same screen — no second,
            // separate "who are you" step. Only fires on the actual
            // pending → accepted transition (not on the silent re-accept a
            // reconnect produces), since `onChange` only triggers on a
            // genuine value change.
            guard authorization == .accepted else { return }
            let trimmed = nickname.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return }
            PlayerNickname.save(trimmed)
            client.join(nickname: trimmed, avatar: selectedAvatar)
        }
        .onChange(of: client.phase) { _, phase in
            // Black-out is meant to feel tense: a strong one-off pulse when
            // the lights first go out, then a lighter pulse repeating for as
            // long as the emergency task is active. Respects the player's
            // own haptics toggle (see `SettingsSheet`).
            blackoutPulseTask?.cancel()
            blackoutPulseTask = nil
            guard hapticsEnabled else { return }
            switch phase {
            case .blackoutReveal:
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            case .blackoutTask:
                blackoutPulseTask = Task {
                    let generator = UIImpactFeedbackGenerator(style: .heavy)
                    while !Task.isCancelled {
                        generator.impactOccurred()
                        try? await Task.sleep(for: .seconds(1.5))
                    }
                }
            default:
                break
            }
        }
        .onAppear {
            // Every screen in this app — the turn-order minigames and the
            // Black-out tasks most of all — is laid out for landscape, so
            // the whole controller stays landscape-only rather than
            // rotating per phase.
            requestOrientation(.landscape)
        }
        .sheet(item: $suspectDetail) { suspect in
            SuspectDetailView(suspect: suspect)
        }
    }

    /// Restricts the interface to `orientations`, prompting the system to
    /// rotate into it immediately regardless of how the phone is physically
    /// held. No-ops if there's no active window scene to reorient.
    private func requestOrientation(_ orientations: UIInterfaceOrientationMask) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations)) { _ in }
    }

    /// Retries discovery with a short backoff (2s, 4s, 8s, capped at 15s).
    /// After `maxAutoReconnectAttempts` this stops retrying automatically —
    /// `connectView` then shows a manual "Retry" button instead of
    /// looping forever on its own.
    private func retryConnection() {
        guard reconnectAttempts < Self.maxAutoReconnectAttempts else { return }
        let delaySeconds = min(2 * (1 << reconnectAttempts), 15)
        reconnectAttempts += 1
        Task {
            try? await Task.sleep(for: .seconds(delaySeconds))
            guard client.connectionState == .disconnected || client.connectionState == .connecting else { return }
            client.startBrowsing()
        }
    }

    private var background: some View {
        LinearGradient(colors: [.phoenixBackground, .phoenixGreenDark.opacity(0.3)], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }

    @ViewBuilder
    private var content: some View {
        switch client.connectionState {
        case .idle, .browsing, .disconnected:
            connectView
        case .connecting:
            statusView(icon: "antenna.radiowaves.left.and.right", title: "Connecting…", subtitle: nil)
        case .connected:
            if client.joinAuthorization == .accepted {
                profileView
            } else {
                codeEntryView
            }
        }
    }

    /// True once both the nickname and the 4-digit code are filled in,
    /// gating the Join button.
    private var canSubmitJoin: Bool {
        !nickname.trimmingCharacters(in: .whitespaces).isEmpty && codeInput.count == 4
    }

    private var codeEntryView: some View {
        HStack(spacing: 40) {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.phoenixGold)

                Text("Join the case")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)

                Text("Enter your detective name and the code shown on the Apple TV.")
                    .font(.system(size: 16, design: .rounded))
                    .foregroundStyle(.phoenixMuted)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 16) {
                Spacer()

                TextField("Your detective name", text: $nickname)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
                    .frame(height: 56)
                    .padding(.horizontal, 16)
                    .background(Color.phoenixCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                    )

                TextField("0000", text: $codeInput)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(height: 64)
                    .background(Color.phoenixCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .onChange(of: codeInput) { _, newValue in
                        codeInput = String(newValue.filter(\.isNumber).prefix(4))
                    }

                if client.joinAuthorization == .rejected {
                    Label("Wrong code, try again.", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.phoenixDestructive)
                } else if client.joinAuthorization == .timedOut {
                    Label("No response from the Apple TV. Try again.", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.phoenixDestructive)
                }

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    client.requestToJoin(code: codeInput)
                } label: {
                    Group {
                        if client.joinAuthorization == .pending {
                            ProgressView().tint(.white)
                        } else {
                            Text("Join")
                        }
                    }
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                }
                .buttonStyle(PressableButtonStyle(tint: .phoenixGreen))
                .disabled(!canSubmitJoin || client.joinAuthorization == .pending)

                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 20)
    }

    /// The shared "big icon on the left, content on the right" frame used by
    /// every simple status-style screen (connecting, waiting for a turn,
    /// locked for a vote, victory, …) — landscape-friendly and avoids
    /// repeating the same `HStack` skeleton in each one.
    @ViewBuilder
    private func landscapeStatus<Content: View>(
        icon: String,
        iconColor: Color = .phoenixGold,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 36) {
            Image(systemName: icon)
                .font(.system(size: 64))
                .foregroundStyle(iconColor)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 14) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 50)
    }

    private var connectView: some View {
        landscapeStatus(icon: "magnifyingglass") {
            Text("Looking for the Phoenix Academy Apple TV…")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            if client.connectionState == .disconnected && reconnectAttempts >= Self.maxAutoReconnectAttempts {
                Label("Can't find the Apple TV.", systemImage: "wifi.exclamationmark")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.phoenixDestructive)

                Button {
                    reconnectAttempts = 0
                    client.startBrowsing()
                } label: {
                    Text("Retry")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
                .buttonStyle(PressableButtonStyle(tint: .phoenixGreen))
            } else if client.discoveredHosts.isEmpty {
                ProgressView()
                    .tint(.white)
            } else if client.discoveredHosts.count == 1 {
                Label("Found it! Connecting…", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(.phoenixGreen)
            } else {
                Text("Found more than one Apple TV: pick the right one.")
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(.phoenixMuted)

                VStack(spacing: 10) {
                    ForEach(client.discoveredHosts, id: \.self) { discoveredHost in
                        Button {
                            client.connect(to: discoveredHost)
                        } label: {
                            Label(discoveredHost.displayName, systemImage: "appletv.fill")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                        }
                        .buttonStyle(PressableButtonStyle(tint: .phoenixGreen))
                    }
                }
            }
        }
    }

    
    private var avatarPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(Avatar.allCases) { avatar in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        savedAvatarID = avatar.rawValue
                        syncProfile()
                    } label: {
                        Text(avatar.emoji)
                            .font(.system(size: 40))
                            .frame(width: 60, height: 60)
                            .background(savedAvatarID == avatar.rawValue ? Color.phoenixGold : Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var profileView: some View {
        Group {
            switch client.phase {
            case .starting:
                statusView(
                    icon: "flashlight.on.fill",
                    title: "The case is about to begin…",
                    subtitle: "Keep your notebook ready!"
                )
            case .introVideo, .rules:
                statusView(
                    icon: "tv.fill",
                    title: "Watch the Apple TV!",
                    subtitle: "The story is about to start…"
                )
            case .minigame:
                minigameView
            case .roomSelection:
                roomSelectionView
            case .notebook:
                notebookView
            case .voting:
                votingView
            case .victory:
                victoryView
            case .blackoutReveal:
                statusView(
                    icon: "bolt.slash.fill",
                    title: "Watch the Apple TV!",
                    subtitle: "Something happened…"
                )
            case .blackoutTask:
                blackoutTaskView
            case .connecting, .lobby:
                lobbyContent
            case .notEnoughPlayers:
                statusView(
                    icon: "person.fill.xmark",
                    title: "Not enough detectives…",
                    subtitle: "Waiting for the host to restart the case."
                )
            }
        }
    }

    @ViewBuilder
    private var minigameView: some View {
        if client.hasFinishedMinigame {
            landscapeStatus(icon: "checkmark.seal.fill") {
                Text(minigameFinishedText)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Wait for the other detectives…")
                    .font(.system(size: 16, design: .rounded))
                    .foregroundStyle(.phoenixMuted)

                ProgressView()
                    .tint(.white)
            }
        } else {
            activeTurnMinigameView
        }
    }

    /// Dispatches to whichever of the 13 turn-order minigames the host
    /// rolled for this round (see `GameSession.turnMinigame`). Every one of
    /// them calls `client.finishMinigame()` through `onComplete` once
    /// solved; arrival order there is what sets this round's turn order and
    /// penalty, exactly like the rest.
    @ViewBuilder
    private var activeTurnMinigameView: some View {
        switch client.turnMinigame {
        case .numberMemory:
            TurnNumberMemoryView(onComplete: client.finishMinigame)
        case .holdRelease:
            TurnHoldReleaseView(onComplete: client.finishMinigame)
        case .tapInOrder:
            TurnTapInOrderView(onComplete: client.finishMinigame)
        case .magneticRings:
            TurnMagneticRingsView(onComplete: client.finishMinigame)
        case .shakeCharge:
            TurnShakeChargeView(onComplete: client.finishMinigame)
        case .swipeCardPace:
            TurnSwipeCardPaceView(onComplete: client.finishMinigame)
        case .crimeMemoryMatch:
            TurnCrimeMemoryMatchView(onComplete: client.finishMinigame)
        case .captchaReveal:
            TurnCaptchaRevealView(onComplete: client.finishMinigame)
        case .tiltAim:
            TurnTiltAimView(onComplete: client.finishMinigame)
        case .buttonMashing:
            TurnButtonMashingView(onComplete: client.finishMinigame)
        case .scratchPin:
            TurnScratchPinView(onComplete: client.finishMinigame)
        case .keyFitting:
            TurnKeyFittingView(onComplete: client.finishMinigame)
        case .validCardSwipe:
            TurnValidCardSwipeView(onComplete: client.finishMinigame)
        }
    }

    private var minigameFinishedText: String {
        guard let position = client.minigameFinishOrder.firstIndex(of: client.localPlayerID) else {
            return "Great job!"
        }
        return "You finished in place #\(position + 1)!"
    }

    private var hasFinishedBlackoutTask: Bool {
        client.blackoutTaskFinishedPlayerIDs.contains(client.localPlayerID)
    }

    @ViewBuilder
    private var blackoutTaskView: some View {
        if hasFinishedBlackoutTask {
            landscapeStatus(icon: "checkmark.seal.fill") {
                Text("Done!")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Wait for the other detectives…")
                    .font(.system(size: 16, design: .rounded))
                    .foregroundStyle(.phoenixMuted)

                ProgressView()
                    .tint(.white)
            }
        } else {
            switch client.blackoutMinigame {
            case .lightRegulator:
                BlackoutLightRegulatorView(client: client)
            case .overvoltageWhack:
                BlackoutOvervoltageWhackView {
                    client.finishBlackoutTask()
                }
            case .pistonSync:
                BlackoutPistonSyncView {
                    client.finishBlackoutTask()
                }
            }
        }
    }

    private var roomSelectionView: some View {
        Group {
            if let secondsRemaining = roomFindingSecondsRemaining, let finding = client.myRoomFinding {
                roomFindingView(finding, secondsRemaining: secondsRemaining)
            } else if client.isMyTurnToChooseRoom {
                roomChoiceView
            } else {
                waitingForTurnView
            }
        }
        .onChange(of: client.myRoomFinding) { _, finding in
            guard finding != nil else { return }
            roomFindingCountdownTask?.cancel()
            roomFindingCountdownTask = Task {
                for remaining in stride(from: Self.roomReadingSeconds, through: 1, by: -1) {
                    guard !Task.isCancelled else { return }
                    roomFindingSecondsRemaining = remaining
                    try? await Task.sleep(for: .seconds(1))
                }
                guard !Task.isCancelled else { return }
                roomFindingSecondsRemaining = nil
            }
        }
    }

    private var currentTurnPlayer: Player? {
        guard client.turnOrder.indices.contains(client.currentTurnIndex) else { return nil }
        let id = client.turnOrder[client.currentTurnIndex]
        return client.players.first { $0.id == id }
    }

    /// Shown to everyone except the current turn holder. Turns now advance
    /// as fast as players pick (no per-turn wait), so this is a brief beat
    /// rather than something with its own countdown — nobody's clue is
    /// revealed yet either way, since the host holds every finding back
    /// until the whole round is done (see `roomFindingView`).
    private var waitingForTurnView: some View {
        landscapeStatus(icon: "hourglass") {
            Text(currentTurnPlayer.map { "\($0.nickname)'s turn…" } ?? "Waiting for the next turn…")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            Text("Watch the board on the Apple TV!")
                .font(.system(size: 16, design: .rounded))
                .foregroundStyle(.phoenixMuted)
            ProgressView()
                .tint(.white)
        }
    }

    private var roomChoiceView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("SELECT LOCATION")
                .font(.system(size: 24, weight: .black, design: .monospaced))
                .foregroundStyle(Color.phoenixGold)
                .tracking(4)
                .padding(.horizontal, 20)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(RoomID.allCases) { room in
                        let isTaken = client.roomVisitLog.contains { $0.roomID == room }
                        Button {
                            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                            client.chooseRoom(room)
                        } label: {
                            VStack(spacing: 12) {
                                Image(systemName: room.icon)
                                    .font(.system(size: 40, weight: .light))
                                    .foregroundStyle(isTaken ? Color.gray : Color.phoenixGold)
                                
                                Text(room.displayName.uppercased())
                                    .font(.system(size: 16, weight: .black, design: .monospaced))
                                    .foregroundStyle(isTaken ? Color.gray : .white)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(width: 200, height: 260)
                            .background(
                                ZStack {
                                    isTaken ? Color.black.opacity(0.8) : Color.white.opacity(0.05)
                                }
                            )
                            .overlay(Rectangle().strokeBorder(isTaken ? Color.gray.opacity(0.3) : Color.phoenixGold, lineWidth: 2))
                            .overlay {
                                if isTaken {
                                    Image(systemName: "slash.circle.fill")
                                        .font(.system(size: 60))
                                        .foregroundStyle(Color.red.opacity(0.7))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isTaken)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func roomFindingView(_ finding: RoomFinding, secondsRemaining: Int) -> some View {
        HStack(spacing: 40) {
            // Left side: Timer
            VStack {
                Text("\(secondsRemaining)")
                    .font(.system(size: 60, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 120, height: 120)
                    .background(roomFindingIconColor(finding).opacity(0.2), in: Circle())
                    .overlay(Circle().strokeBorder(roomFindingIconColor(finding), lineWidth: 4))
                    .shadow(color: roomFindingIconColor(finding).opacity(0.5), radius: 10)
            }

            // Right side: Content Card
            VStack(spacing: 16) {
                Image(systemName: roomFindingIcon(finding))
                    .font(.system(size: 50))
                    .foregroundStyle(roomFindingIconColor(finding))
                    .shadow(color: roomFindingIconColor(finding).opacity(0.5), radius: 10)
                
                VStack(spacing: 8) {
                    switch finding {
                    case .clue(let clue):
                        Text(clue.title)
                            .font(.system(size: 24, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Text(clue.text)
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    case .empty:
                        Text("This area is clear")
                            .font(.system(size: 24, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Nothing to see here. Time to move on.")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                    case .hiddenByPenalty:
                        Text("Visibility compromised")
                            .font(.system(size: 24, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Text("You were too slow in the emergency task. Any clues here are hidden in darkness.")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.4), .clear], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5)
            )
            .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
        }
        .padding(.horizontal, 40)
    }

    private func roomFindingIcon(_ finding: RoomFinding) -> String {
        switch finding {
        case .clue: return "doc.text.magnifyingglass"
        case .empty: return "door.left.hand.closed"
        case .hiddenByPenalty: return "eye.slash.fill"
        }
    }

    private func roomFindingIconColor(_ finding: RoomFinding) -> Color {
        switch finding {
        case .clue: return .phoenixGold
        case .empty: return .phoenixMuted
        case .hiddenByPenalty: return .phoenixDestructive
        }
    }

    private var notebookView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                Text("SUSPECT DATABASE")
                    .font(.system(size: 22, weight: .black, design: .monospaced))
                    .foregroundStyle(.white)
                    .tracking(4)
                    .padding(.top, 20)
                    .padding(.bottom, 10)

                if let accusation = client.lastAccusation, !accusation.wasCorrect, accusation.playerID == client.localPlayerID {
                    wrongAccusationBanner(accusation)
                        .padding(.bottom, 10)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 20) {
                        ForEach(Suspects.all) { suspect in
                            let isExcluded = excludedSuspectIDs.contains(suspect.id)
                            
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                if isExcluded {
                                    excludedSuspectIDs.remove(suspect.id)
                                } else {
                                    excludedSuspectIDs.insert(suspect.id)
                                }
                            } label: {
                                VStack(spacing: 0) {
                                    Image(suspect.name) // Asset name is the color like "Blue"
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 160, height: 200)
                                        .clipped()
                                        .opacity(isExcluded ? 0.3 : 1.0)
                                    
                                    Text(suspect.name.uppercased())
                                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                                        .foregroundStyle(.white)
                                        .frame(height: 50)
                                        .frame(maxWidth: .infinity)
                                        .background(suspect.color.color.opacity(0.8))
                                }
                                .frame(width: 160)
                                .background(Color.black)
                                .overlay(Rectangle().strokeBorder(isExcluded ? Color.red : suspect.color.color, lineWidth: 2))
                                .overlay {
                                    if isExcluded {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 80, weight: .black))
                                            .foregroundStyle(.red)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 40)
                    .padding(.vertical, 20)
                }
                
                if client.isCurrentRoundBlackout {
                    Text("VOTING OFFLINE - BLACKOUT")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.phoenixGold)
                        .padding(.bottom, 20)
                } else {
                    let hasFailed = client.failedAccusationPlayerIDs.contains(client.localPlayerID)
                    Button {
                        UINotificationFeedbackGenerator().notificationOccurred(.warning)
                        client.startVoting()
                    } label: {
                        Text(hasFailed ? "ACCUSATION FAILED" : "INITIATE ACCUSATION")
                            .font(.system(size: 20, weight: .black, design: .monospaced))
                            .foregroundStyle(hasFailed ? .white.opacity(0.5) : .black)
                            .padding(.horizontal, 40)
                            .padding(.vertical, 16)
                            .background(hasFailed ? Color.red.opacity(0.3) : Color.phoenixDestructive)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(hasFailed)
                    .padding(.bottom, 20)
                }
            }
        }
    }

    private func wrongAccusationBanner(_ accusation: Accusation) -> some View {
        let accuserName = client.players.first { $0.id == accusation.playerID }?.nickname ?? "A player"
        let suspectName = Suspects.all.first { $0.id == accusation.suspectID }?.name ?? "someone"
        return Label("\(accuserName) accused \(suspectName) — wrong! The game continues.", systemImage: "xmark.circle.fill")
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(.phoenixDestructive)
            .padding(12)
            .phoenixCardStyle(cornerRadius: 14)
    }

    private var votingView: some View {
        Group {
            if client.votingPlayerID == client.localPlayerID {
                accusationPickerView
            } else {
                lockedForVoteView
            }
        }
        .onChange(of: client.votingPlayerID) { _, votingPlayerID in
            guard votingPlayerID != nil, votingPlayerID != client.localPlayerID else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }

    private var lockedForVoteView: some View {
        landscapeStatus(icon: "lock.fill", iconColor: .phoenixDestructive) {
            Text(votingPlayerName.map { "\($0) is voting…" } ?? "Someone is voting…")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            Text("Wait for the result on the board.")
                .font(.system(size: 16, design: .rounded))
                .foregroundStyle(.phoenixMuted)
        }
    }

    private var votingPlayerName: String? {
        guard let id = client.votingPlayerID else { return nil }
        return client.players.first { $0.id == id }?.nickname
    }

    private var accusationPickerView: some View {
        ZStack {
            LinearGradient(colors: [Color.red.opacity(0.4), Color.black], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    Text("WHO DO YOU ACCUSE?")
                        .font(.system(size: 24, weight: .black, design: .monospaced))
                        .foregroundStyle(.white)
                        .tracking(4)
                        .padding(.top, 20)

                    Text("Choose carefully: if you're wrong, the game continues but you'll have lost your chance.")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 20) {
                            ForEach(Suspects.all) { suspect in
                                let isSelected = accusationCandidate?.id == suspect.id
                                Button {
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    accusationCandidate = suspect
                                } label: {
                                    VStack(spacing: 0) {
                                        Image(suspect.name) // Same size as notebook
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 160, height: 200)
                                            .clipped()
                                        
                                        Text(suspect.name.uppercased())
                                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                                            .foregroundStyle(.white)
                                            .frame(height: 50)
                                            .frame(maxWidth: .infinity)
                                            .background(suspect.color.color.opacity(0.8))
                                    }
                                    .frame(width: 160)
                                    .background(Color.black)
                                    .overlay(Rectangle().strokeBorder(isSelected ? Color.white : suspect.color.color, lineWidth: isSelected ? 4 : 2))
                                    .shadow(color: isSelected ? .white.opacity(0.5) : .clear, radius: 10)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 40)
                        .padding(.vertical, 10)
                    }

                    if let candidate = accusationCandidate {
                        Button {
                            client.castAccusation(suspectID: candidate.id)
                            accusationCandidate = nil
                        } label: {
                            Text("CONFIRM ACCUSATION: \(candidate.name.uppercased())")
                                .font(.system(size: 20, weight: .black, design: .monospaced))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 40)
                                .padding(.vertical, 16)
                                .background(Color.red)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .shadow(color: .red.opacity(0.5), radius: 10, y: 5)
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 20)
                    } else {
                        Spacer().frame(height: 52)
                            .padding(.bottom, 20)
                    }
                }
            }
        }
    }

    private var victoryView: some View {
        landscapeStatus(icon: "trophy.fill") {
            Text("CASE SOLVED!")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)

            if let accusation = client.lastAccusation {
                let winnerName = client.players.first { $0.id == accusation.playerID }?.nickname ?? "A detective"
                let culpritName = Suspects.all.first { $0.id == accusation.suspectID }?.name ?? "the culprit"
                Text("\(winnerName) exposed \(culpritName) and wins the scholarship!")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func statusView(icon: String, title: String, subtitle: String?) -> some View {
        landscapeStatus(icon: icon) {
            Text(title)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 16, design: .rounded))
                    .foregroundStyle(.phoenixMuted)
            }

            ProgressView()
                .tint(.white)
        }
    }

    private var lobbyContent: some View {
        ScrollView(.vertical) {
            HStack(alignment: .top, spacing: 24) {
                VStack(spacing: 16) {
                    profileCard
                    readyButton
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)

                if !client.players.isEmpty {
                    playersCard
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    /// Compact identity row instead of a big "fill this in" card: the
    /// nickname was already entered (and saved) on the join screen, so this
    /// is just a lightweight way to fix a typo, not the primary prompt.
    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Your detective name", systemImage: "person.text.rectangle.fill")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.phoenixMuted)

            TextField("Your name", text: $nickname)
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundStyle(.white)
                .tint(.phoenixGold)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
                .onChange(of: nickname) { _, newValue in
                    PlayerNickname.save(newValue)
                    syncProfile()
                }
        }
        .padding(16)
        .phoenixCardStyle(cornerRadius: 16)
    }

    private var readyButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            client.setReady(!isReady)
        } label: {
            Label(
                isReady ? "You're ready! Tap to cancel" : "Ready to investigate!",
                systemImage: isReady ? "checkmark.circle.fill" : "flag.checkered"
            )
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .frame(maxWidth: .infinity)
            .frame(height: 56)
        }
        .buttonStyle(PressableButtonStyle(tint: isReady ? .phoenixDestructive : .phoenixGreen))
        .disabled(nickname.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    private var playersCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Connected players", systemImage: "person.2.fill")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            VStack(spacing: 10) {
                ForEach(client.players) { player in
                    HStack(spacing: 12) {
                        AvatarBadge(player: player, diameter: 36)

                        Text(player.nickname)
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundStyle(.white)

                        Spacer()

                        Label(
                            player.isReady ? "Ready" : "Waiting",
                            systemImage: player.isReady ? "checkmark.circle.fill" : "clock.fill"
                        )
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(player.isReady ? .phoenixGreen : .phoenixMuted)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(20)
        .phoenixCardStyle()
    }

    /// Sends the current nickname to the host: a `join` the first time
    /// (before we appear in `client.players`), an `updateProfile` afterwards.
    private func syncProfile() {
        let trimmed = nickname.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if myPlayer == nil {
            client.join(nickname: trimmed, avatar: selectedAvatar)
        } else {
            client.updateProfile(nickname: trimmed, avatar: selectedAvatar)
        }
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
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [.phoenixCard, .phoenixGreenDark], startPoint: .top, endPoint: .bottom)
            Image(systemName: suspect.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 34, height: 34)
                .foregroundStyle(.white.opacity(0.35))
        }
    }
}

private struct SuspectRow: View {
    let suspect: Suspect
    let isExcluded: Bool
    let onToggle: () -> Void
    /// Opens the full-screen portrait + detail sheet — a separate tap
    /// target from the row itself, so viewing a suspect up close never
    /// gets confused with ruling them out.
    let onShowDetail: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            SuspectPortraitView(suspect: suspect)
                .frame(width: 56, height: 74)
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(suspect.color.color)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1))
                        .padding(3)
                }
                .grayscale(isExcluded ? 1 : 0)
                .opacity(isExcluded ? 0.5 : 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(suspect.name)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .strikethrough(isExcluded)
                Text(suspect.role)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(isExcluded ? .phoenixMuted : Color.phoenixGold)
                Text(suspect.detail)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.phoenixMuted)
            }
            .foregroundStyle(isExcluded ? Color.phoenixMuted : .white)

            Spacer()

            Button(action: onShowDetail) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.phoenixGold)
            }
            .buttonStyle(.plain)

            Image(systemName: isExcluded ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22))
                .foregroundStyle(isExcluded ? Color.phoenixGreen : .white.opacity(0.3))
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .padding(16)
        .opacity(isExcluded ? 0.75 : 1)
        .phoenixCardStyle(cornerRadius: 18)
    }
}

/// Full-screen portrait + details for a suspect, opened from `SuspectRow`'s
/// info button in the notebook.
private struct SuspectDetailView: View {
    let suspect: Suspect
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.phoenixMuted)
                }
            }

            SuspectPortraitView(suspect: suspect)
                .frame(height: 320)

            Text(suspect.name)
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)

            Text(suspect.role)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.phoenixGold)

            Text(suspect.detail)
                .font(.system(size: 16, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            VStack(alignment: .leading, spacing: 10) {
                CaseColorTag(color: suspect.color)
                EvidenceTraitList(suspect: suspect)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .phoenixCardStyle(cornerRadius: 16)
            .padding(.horizontal, 24)

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.phoenixBackground.ignoresSafeArea())
    }
}

#Preview {
    ContentView()
}
