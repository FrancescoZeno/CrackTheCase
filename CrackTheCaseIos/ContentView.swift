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
    /// Which room this player most recently chose — `RoomFinding` itself
    /// deliberately never carries a `RoomID` (see `Room.swift`), so this is
    /// tracked locally purely to pick the right `RoomID.clueAsset` photo for
    /// `roomFindingView`, without touching the wire protocol.
    @State private var lastChosenRoom: RoomID?
    /// Every distinct clue this player has personally found so far this
    /// game, in the room it was found — purely local (never sent to the
    /// host, matching the "local-only vs networked state" pattern used
    /// elsewhere). Drives both the notebook's clue list and the "3 clues
    /// collected" gate on casting an accusation.
    @State private var collectedClues: [(room: RoomID, clue: Clue)] = []
    @State private var reconnectAttempts = 0
    /// Suspects this player has ruled out — purely a personal aid, never
    /// sent to the host.
    @State private var excludedSuspectIDs: Set<String> = []
    /// Suspects this player has personally accused and gotten wrong,
    /// accumulated across every round this game (not just the current
    /// round's `client.failedAccusationPlayerIDs`, which the host resets
    /// each round) — so once a guess is known wrong, it stays ruled out on
    /// this player's own notebook instead of being a live option again next
    /// round. Purely local UI state, derived by watching `client.lastAccusation`.
    @State private var wronglyAccusedSuspectIDs: Set<String> = []
    @State private var accusationCandidate: Suspect?
    @State private var showSettings = false
    /// Backs the persistent "leave game" corner button's confirmation — see
    /// `leaveGameButton`. Without this control, a player had no way to bail
    /// out of a game in progress; only `victoryView`/`defeatView` offered a
    /// way back to `homeScreen`.
    @State private var showLeaveConfirmation = false
    #if DEBUG
    @State private var showMinigameDebugMenu = false
    #endif
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

    @State private var isAtHome = true
    /// True while the device's *physical* orientation (accelerometer, via
    /// `UIDevice.current.orientation` — independent of how the interface is
    /// actually being drawn) is portrait. The app is landscape-only (see
    /// `requestOrientation` and the target's `UISupportedInterfaceOrientations`),
    /// which already makes iOS render it in landscape regardless of the
    /// physical rotation lock in Control Center — but that doesn't stop a
    /// player from holding the phone upright while the content is drawn
    /// sideways; this drives the "please rotate" overlay for that case.
    @State private var isDevicePhysicallyPortrait = false

    var body: some View {
        ZStack {
            if isAtHome {
                homeScreen
            } else {
                // `background` (`CinematicBackground`) calls
                // `.ignoresSafeArea()` internally. Stacking it as a
                // *sibling* of `content` in a `ZStack` (a previous
                // structure) made the WHOLE `ZStack` adopt that
                // safe-area-ignoring frame as its own — every
                // `.overlay(alignment:)` attached to it, and `content`
                // itself, then laid out against the true physical screen
                // edges instead of the safe area, landing inside the
                // home-indicator/notch exclusion zones.
                //
                // `.background()` instead of `ZStack` avoids the leak:
                // `background` is sized to match `content`'s own
                // (safe-area-respecting) frame rather than the other way
                // around, so `content` and the overlay below correctly
                // align to the real safe area while the background still
                // paints edge-to-edge.
                //
                // No game-clock overlay here (unlike the tvOS board) — the
                // shared countdown lives only on the TV; a second, phone-
                // side copy was never able to find a spot that didn't
                // collide with something else (the minigame Skip button up
                // top, the home indicator down low), and the game only has
                // one clock that matters to the whole table anyway.
                content
                    .background {
                        background.ignoresSafeArea()
                    }
                    .overlay(alignment: .topLeading) {
                        leaveGameButton
                    }
            }

            if isDevicePhysicallyPortrait {
                rotateDevicePrompt
            }
        }
        .tint(.phoenixGold)
        .onAppear {
            client.startBrowsing()
            Haptics.prepareAll()
        }
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
            // The host re-rolls the culprit every time it returns to
            // `.lobby` (both "Play Again" and the notEnoughPlayers
            // acknowledgment call `GameSession.resetToLobby()`), but this
            // phone's own notebook marks are local UI state the host never
            // touches — without this, a suspect ruled out (or wrongly
            // accused) last game would still show that way against a
            // brand-new culprit.
            if phase == .lobby {
                excludedSuspectIDs = []
                wronglyAccusedSuspectIDs = []
                collectedClues = []
            }

            // The Taptic Engine can go dormant after a stretch of no
            // haptics (e.g. sitting through the notebook/voting phases) and
            // `.prepare()`d state doesn't last forever — re-prime right as
            // a fresh minigame or Black-out task begins, on top of the
            // one-time launch priming in the top-level `onAppear` above, so
            // the very first tap/shake/etc. of each round fires promptly.
            if phase == .minigame || phase == .blackoutTask {
                Haptics.prepareAll()
            }

            // Black-out is meant to feel tense: a strong one-off pulse when
            // the lights first go out, then a lighter pulse repeating for as
            // long as the emergency task is active. Respects the player's
            // own haptics toggle (see `SettingsSheet`).
            blackoutPulseTask?.cancel()
            blackoutPulseTask = nil
            guard hapticsEnabled else { return }
            switch phase {
            case .blackoutReveal:
                Haptics.notify(.warning)
                Haptics.vibrate()
            case .blackoutTask:
                blackoutPulseTask = Task {
                    while !Task.isCancelled {
                        Haptics.impact(.heavy)
                        Haptics.vibrate()
                        try? await Task.sleep(for: .seconds(1.5))
                    }
                }
            default:
                break
            }
        }
        // A single, uniform "you're done" pulse the instant any task
        // finishes — turn-order minigame or Black-out task alike. Deliberately
        // centralized here instead of wired into each of the 16 individual
        // minigame views: some already fire their own richer in-game haptics
        // (a different purpose — feedback *during* play), and the cooperative
        // `lightRegulator` Black-out task has no per-player `onComplete`
        // closure at all (it completes once the shared average hits the
        // target), so only watching these two host-driven "finished" signals
        // covers every case uniformly.
        .onChange(of: client.hasFinishedMinigame) { _, finished in
            guard finished else { return }
            Haptics.impact(.light)
        }
        .onChange(of: hasFinishedBlackoutTask) { _, finished in
            guard finished else { return }
            Haptics.impact(.light)
        }
        .onChange(of: client.lastAccusation) { _, accusation in
            // Once this player's own guess comes back wrong, that suspect
            // is a known dead end — remember it here (across rounds, unlike
            // the host's per-round `failedAccusationPlayerIDs`) so the
            // notebook can rule it out for good instead of leaving it
            // choosable again next round.
            guard let accusation, !accusation.wasCorrect, accusation.playerID == client.localPlayerID else { return }
            wronglyAccusedSuspectIDs.insert(accusation.suspectID)
        }
        .onAppear {
            // Every screen in this app — the turn-order minigames and the
            // Black-out tasks most of all — is laid out for landscape, so
            // the whole controller stays landscape-only rather than
            // rotating per phase. The target's `UISupportedInterfaceOrientations`
            // only lists landscape orientations, which already forces iOS to
            // render this app in landscape regardless of the Control Center
            // rotation lock (a locked app can't be "unlocked into" an
            // orientation it doesn't support in the first place) — this call
            // additionally nudges an already-running scene that's still
            // mid-transition, and is re-invoked by `rotateDevicePrompt`'s
            // button below.
            requestOrientation(.landscape)
            // `UIDevice.orientation` doesn't update on its own — device
            // orientation notifications must be explicitly turned on, and
            // it's this app's job to turn them back off (see `.onDisappear`).
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        }
        .onDisappear {
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            switch UIDevice.current.orientation {
            case .portrait, .portraitUpsideDown:
                isDevicePhysicallyPortrait = true
            case .landscapeLeft, .landscapeRight:
                isDevicePhysicallyPortrait = false
            case .faceUp, .faceDown, .unknown:
                // Ambiguous — the phone is flat or the sensor can't tell.
                // Leave whatever's currently showing alone rather than
                // flipping the prompt on/off on every tiny wobble.
                break
            @unknown default:
                break
            }
        }
    }

    /// Full-screen fallback for when the interface renders landscape (this
    /// app is landscape-only — see the `.onAppear` above) but the player is
    /// still physically holding the phone upright. Includes a button that
    /// re-asks the system to rotate: per Apple's documentation,
    /// `requestGeometryUpdate` can override the Control Center rotation
    /// lock for an orientation the app actually supports, which landscape
    /// is (and portrait no longer is).
    ///
    /// Deliberately **not** counter-rotated to face the player upright:
    /// getting that rotation direction right depends on exactly which
    /// landscape orientation the system picked and exactly how the phone is
    /// tilted, and guessing wrong (upside-down or mirrored) without a real
    /// device to check on would be worse than just leaving it landscape —
    /// the same static "please rotate" pattern most landscape-only apps use,
    /// readable at a tilt either way.
    private var rotateDevicePrompt: some View {
        ZStack {
            Color.phoenixBackground.ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "rotate.right.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.phoenixGold)
                    .symbolEffect(.pulse)

                Text("ROTATE YOUR PHONE")
                    .font(.system(size: 24, weight: .black, design: .monospaced))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("This game only plays in landscape.")
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(.phoenixMuted)
                    .multilineTextAlignment(.center)

                Button {
                    Haptics.impact(.light)
                    requestOrientation(.landscape)
                } label: {
                    Text("ROTATE FOR ME")
                        .font(.system(size: 15, weight: .black, design: .monospaced))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 14)
                        .background(Color.phoenixGold, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            .padding(40)
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
        CinematicBackground()
    }

    /// True whenever a persistent way back to `homeScreen` is actually
    /// useful — i.e. anywhere from the connect/code-entry screens through
    /// an active game. Hidden on `VictoryView`/`DefeatView`, which already
    /// have their own prominent "Back to Home" button (`BackToHomeButton`)
    /// — showing both would be redundant.
    private var showsPersistentLeaveButton: Bool {
        client.phase != .victory && client.phase != .defeat
    }

    /// Fixed footprint of `leaveGameButton` (outer padding + circle
    /// diameter) — a floating `.overlay(alignment: .topLeading)` (see
    /// `body`), not a space-reserving inset, so no individual phase needs
    /// to know this size or add its own top-clearance padding.
    private static let leaveButtonDiameter: CGFloat = 36
    private static let leaveButtonOuterPadding: CGFloat = 12

    /// Small, unobtrusive corner control so a player is never stuck in a
    /// game (or a stalled connection attempt) with no way out — previously
    /// the only exit was winning or losing. Confirms first since leaving
    /// disconnects this phone from the host.
    @ViewBuilder
    private var leaveGameButton: some View {
        if showsPersistentLeaveButton {
            Button {
                Haptics.impact(.light)
                showLeaveConfirmation = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: Self.leaveButtonDiameter, height: Self.leaveButtonDiameter)
                    .background(.black.opacity(0.35), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Leave game")
            .padding(Self.leaveButtonOuterPadding)
            .confirmationDialog(
                "Leave this game?",
                isPresented: $showLeaveConfirmation,
                titleVisibility: .visible
            ) {
                Button("Leave Game", role: .destructive) {
                    client.disconnect()
                    isAtHome = true
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll disconnect from the current game and return to the home screen.")
            }
        }
    }

    private var homeScreen: some View {
        ZStack {
            LinearGradient(colors: [.black, .phoenixCard], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            // Faint, heavily blurred campus backdrop — same `schoolMap`
            // asset used by `CinematicBackground`.
            Image("schoolMap")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .blur(radius: 22)
                .opacity(0.38)
                .saturation(0.6)
                .ignoresSafeArea()

            VStack(spacing: 30) {
                Spacer()
                
                Text("CRACK THE CASE")
                    .font(.system(size: 40, weight: .black, design: .monospaced))
                    .foregroundStyle(.phoenixGold)
                    .multilineTextAlignment(.center)
                    .shadow(color: .phoenixGold.opacity(0.3), radius: 10, y: 5)
                
                Spacer()
                
                VStack(spacing: 20) {
                    homeActionButton(title: "JOIN A ROOM", icon: "door.left.hand.open") {
                        Haptics.impact(.heavy)
                        isAtHome = false
                    }

                    homeActionButton(title: "SETTINGS", icon: "gearshape.fill") {
                        Haptics.impact(.light)
                        showSettings = true
                    }
                }
                .frame(maxWidth: 400)
                .padding(.bottom, 40)
            }
            .padding(.horizontal, 40)
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet()
        }
    }

    /// A single shared style for both home-screen actions — previously "JOIN
    /// A ROOM" was solid gold and "SETTINGS" was a faint bordered chip, an
    /// inconsistency with no meaning behind it. Both now read as identical
    /// dossier tabs, distinguished only by icon/label (mirrors the tvOS
    /// target's `homeActionButton`).
    private func homeActionButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(Color.phoenixGold)
                .padding(.horizontal, 40)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(Color.phoenixCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.phoenixGold.opacity(0.55), lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
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
        HStack(spacing: 80) {
            VStack(alignment: .leading, spacing: 10) {
                Text("AGENT")
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.phoenixGold)
                    .tracking(6)
                
                Text("CREDENTIALS")
                    .font(.system(size: 60, weight: .black, design: .default))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(spacing: 40) {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("DETECTIVE ALIAS")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.5))
                        
                        TextField("ENTER NAME", text: $nickname)
                            .font(.system(size: 24, weight: .black, design: .monospaced))
                            .foregroundStyle(.white)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.words)
                            .overlay(Rectangle().frame(height: 2).foregroundStyle(Color.phoenixGold), alignment: .bottom)
                            .padding(.bottom, 10)
                        
                        avatarPicker
                            .padding(.top, 10)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ACCESS PIN")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.5))
                        
                        TextField("----", text: $codeInput)
                            .keyboardType(.numberPad)
                            .font(.system(size: 32, weight: .black, design: .monospaced))
                            .foregroundStyle(Color.phoenixGold)
                            .tracking(8)
                            .overlay(Rectangle().frame(height: 2).foregroundStyle(Color.phoenixGold), alignment: .bottom)
                            .onChange(of: codeInput) { _, newValue in
                                codeInput = String(newValue.filter(\.isNumber).prefix(4))
                            }
                    }
                }
                
                if client.joinAuthorization == .rejected {
                    Text("ACCESS DENIED. INCORRECT PIN.")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.phoenixDestructive)
                } else if client.joinAuthorization == .timedOut {
                    Text("CONNECTION TIMEOUT. RETRY.")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.phoenixDestructive)
                }
                
                Button {
                    Haptics.impact(.heavy)
                    client.requestToJoin(code: codeInput)
                } label: {
                    ZStack {
                        if client.joinAuthorization == .pending {
                            ProgressView().tint(.white)
                        } else {
                            Text("AUTHENTICATE")
                                .font(.system(size: 18, weight: .black, design: .monospaced))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.phoenixGold)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .opacity(!canSubmitJoin || client.joinAuthorization == .pending ? 0.5 : 1.0)
                }
                .buttonStyle(.plain)
                .disabled(!canSubmitJoin || client.joinAuthorization == .pending)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 60)
        .contentShape(Rectangle())
        .onTapGesture { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
    }

    private var connectView: some View {
        HStack(spacing: 60) {
            // No full "CRACK THE CASE" wordmark here — the player already
            // saw it once on `homeScreen` a tap ago; repeating the game's
            // own name on the very next screen read as the app introducing
            // itself twice in a row. This heading instead describes what
            // this screen is actually doing.
            VStack(alignment: .leading, spacing: 20) {
                Text("FINDING YOUR CASE")
                    .font(.system(size: 52, weight: .black, design: .default))
                    .foregroundStyle(Color.phoenixGold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .shadow(color: Color.phoenixGold.opacity(0.4), radius: 20)

                Text("INVESTIGATIVE PROTOCOL")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                    .tracking(8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(alignment: .leading, spacing: 30) {
                if client.connectionState == .disconnected && reconnectAttempts >= Self.maxAutoReconnectAttempts {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("CONNECTION FAILED")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundStyle(.phoenixDestructive)

                        Button {
                            reconnectAttempts = 0
                            client.startBrowsing()
                        } label: {
                            Text("RETRY CONNECTION")
                                .font(.system(size: 16, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(Color.white.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)

                        // Retrying only helps if the host will actually come
                        // back — if it's gone for good, this was previously
                        // a dead end with no way off this screen.
                        Button {
                            client.disconnect()
                            isAtHome = true
                        } label: {
                            Text("BACK TO HOME")
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                } else if client.discoveredHosts.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("SCANNING NETWORK...")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundStyle(.phoenixGold)
                        ProgressView()
                            .tint(.phoenixGold)
                    }
                } else if client.discoveredHosts.count == 1 {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("HOST DETECTED")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundStyle(.phoenixGreen)
                        Text("Establishing secure connection...")
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("MULTIPLE HOSTS DETECTED")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundStyle(.phoenixGold)
                        
                        VStack(spacing: 12) {
                            ForEach(client.discoveredHosts, id: \.self) { host in
                                Button {
                                    client.connect(to: host)
                                } label: {
                                    HStack {
                                        Image(systemName: "appletv.fill")
                                            .foregroundStyle(.white)
                                        Text(host.displayName)
                                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                                            .foregroundStyle(.white)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(.phoenixGold)
                                    }
                                    .padding()
                                    .background(Color.white.opacity(0.05))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.1)))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 60)
        .contentShape(Rectangle())
        .onTapGesture { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
    }

    
    private var avatarPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(Avatar.allCases) { avatar in
                    Button {
                        Haptics.impact(.light)
                        savedAvatarID = avatar.rawValue
                        syncProfile()
                    } label: {
                        Image(systemName: avatar.symbolName)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(savedAvatarID == avatar.rawValue ? .black : .white)
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
                NotebookView(
                    roundNumber: client.roundNumber,
                    isCurrentRoundBlackout: client.isCurrentRoundBlackout,
                    localPlayerID: client.localPlayerID,
                    players: client.players,
                    roomVisitLog: client.roomVisitLog,
                    collectedClues: collectedClues,
                    failedAccusationPlayerIDs: client.failedAccusationPlayerIDs,
                    votingBanRoundNumbers: client.votingBanRoundNumbers,
                    lastAccusation: client.lastAccusation,
                    wronglyAccusedSuspectIDs: wronglyAccusedSuspectIDs,
                    onStartVoting: { client.startVoting() },
                    excludedSuspectIDs: $excludedSuspectIDs
                )
            case .voting:
                votingView
            case .victory:
                VictoryView(
                    lastAccusation: client.lastAccusation,
                    players: client.players,
                    onBackToHome: { client.disconnect(); isAtHome = true }
                )
            case .defeat:
                DefeatView(onBackToHome: { client.disconnect(); isAtHome = true })
            case .blackoutReveal:
                statusView(
                    icon: "bolt.slash.fill",
                    title: "Watch the Apple TV!",
                    subtitle: "Something happened…"
                )
            case .blackoutTask:
                blackoutTaskView
            case .connecting, .lobby:
                LobbyContentView(
                    players: client.players,
                    nickname: $nickname,
                    isReady: isReady,
                    onNicknameChanged: {
                        PlayerNickname.save(nickname)
                        syncProfile()
                    },
                    onToggleReady: { client.setReady(!isReady) }
                )
                #if DEBUG
                // Debug-build-only shortcut into every minigame, without
                // waiting for it to come up in a real game. Not surfaced by
                // any visible button today — flip `showMinigameDebugMenu`
                // from the debugger, or wire a button back up, to use it.
                .fullScreenCover(isPresented: $showMinigameDebugMenu) {
                    MinigameDebugMenuView(client: client)
                }
                #endif
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
            // Whether this player is the arrival that completed the group —
            // always penalized (see `GameSession.recordMinigameFinish`/
            // `skipMinigame`), whether by actually finishing dead last or by
            // skipping. That penalty is otherwise invisible until this
            // player happens to land on one of the 3 clue rooms during
            // `.roomSelection` (an empty room looks identical either way),
            // so it's called out here immediately instead of only being
            // discoverable much later.
            let isPenalized = client.penalizedPlayerIDs.contains(client.localPlayerID)
            LandscapeStatusView(
                icon: isPenalized ? "exclamationmark.triangle.fill" : "checkmark.seal.fill",
                iconColor: isPenalized ? .phoenixDestructive : .phoenixGold
            ) {
                Text(minigameFinishedText)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                if isPenalized {
                    Text("You were last — your clue will stay hidden this round.")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.phoenixDestructive)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("Wait for the other detectives…")
                    .font(.system(size: 16, design: .rounded))
                    .foregroundStyle(.phoenixMuted)

                ProgressView()
                    .tint(.white)
            }
        } else {
            // `safeAreaInset` (rather than a `ZStack` overlay) reserves its
            // own space above the minigame instead of floating over it, so
            // the bar can never cover part of a landscape-cramped minigame's
            // own top content.
            activeTurnMinigameView
                .safeAreaInset(edge: .top) {
                    // Shown once someone (possibly this player) has
                    // finished — the host is the real authority on when the
                    // grace period actually expires (see
                    // `HostConnectivityService`'s deadline task), this is
                    // just the on-screen countdown plus a way to bail out
                    // early instead of waiting it out.
                    if let firstFinishAt = client.minigameFirstFinishAt {
                        SkipCountdownBar(
                            deadline: firstFinishAt.addingTimeInterval(GameSession.minigameSkipGracePeriod),
                            buttonTitle: "SKIP (clue hidden)",
                            onSkip: client.skipMinigame
                        )
                    }
                }
        }
    }

    /// Dispatches to whichever of the 12 turn-order minigames the host
    /// rolled for this round (see `GameSession.turnMinigame`). Every one of
    /// them calls `client.finishMinigame()` through `onComplete` once
    /// solved; arrival order there is what sets this round's turn order and
    /// penalty, exactly like the rest.
    /// `numberMemory`/`holdRelease`/`tapInOrder`/`magneticRings`/`shakeCharge`/
    /// `swipeCardPace`/`captchaReveal`/`scratchPin` have no
    /// pre-game phase of their own — some (`tapInOrder`) start a timer the
    /// instant they appear — so they're wrapped in `MinigameIntroGate` to
    /// guarantee at least 5s of reading the instructions before they even
    /// mount. `crimeMemoryMatch`/`buttonMashing`/`tiltAim`/`validCardSwipe`
    /// already have their own ≥5s countdown before becoming interactive
    /// (see each file), so wrapping them too would just stack a redundant
    /// second wait — they're constructed directly instead.
    @ViewBuilder
    private var activeTurnMinigameView: some View {
        switch client.turnMinigame {
        case .numberMemory:
            gated(client.turnMinigame) { TurnNumberMemoryView(onComplete: client.finishMinigame) }
        case .holdRelease:
            gated(client.turnMinigame) { TurnHoldReleaseView(onComplete: client.finishMinigame) }
        case .tapInOrder:
            gated(client.turnMinigame) { TurnTapInOrderView(onComplete: client.finishMinigame) }
        case .magneticRings:
            gated(client.turnMinigame) { TurnMagneticRingsView(onComplete: client.finishMinigame) }
        case .shakeCharge:
            gated(client.turnMinigame) { TurnShakeChargeView(onComplete: client.finishMinigame) }
        case .swipeCardPace:
            gated(client.turnMinigame) { TurnSwipeCardPaceView(onComplete: client.finishMinigame) }
        case .crimeMemoryMatch:
            TurnCrimeMemoryMatchView(onComplete: client.finishMinigame)
        case .captchaReveal:
            gated(client.turnMinigame) { TurnCaptchaRevealView(onComplete: client.finishMinigame) }
        case .tiltAim:
            TurnTiltAimView(onComplete: client.finishMinigame)
        case .buttonMashing:
            TurnButtonMashingView(onComplete: client.finishMinigame)
        case .scratchPin:
            gated(client.turnMinigame) { TurnScratchPinView(onComplete: client.finishMinigame) }
        case .validCardSwipe:
            TurnValidCardSwipeView(onComplete: client.finishMinigame)
        }
    }

    private func gated<Game: View>(_ minigame: TurnMinigame, @ViewBuilder game: @escaping () -> Game) -> some View {
        MinigameIntroGate(title: minigame.displayTitle, instruction: minigame.instructionText, game: game)
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
            LandscapeStatusView(icon: "checkmark.seal.fill") {
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
            Group {
                switch client.blackoutMinigame {
                case .lightRegulator:
                    MinigameIntroGate(title: client.blackoutMinigame.displayTitle, instruction: client.blackoutMinigame.instructionText) {
                        BlackoutLightRegulatorView(client: client)
                    }
                case .overvoltageWhack:
                    MinigameIntroGate(title: client.blackoutMinigame.displayTitle, instruction: client.blackoutMinigame.instructionText) {
                        BlackoutOvervoltageWhackView {
                            client.finishBlackoutTask()
                        }
                    }
                case .pistonSync:
                    MinigameIntroGate(title: client.blackoutMinigame.displayTitle, instruction: client.blackoutMinigame.instructionText) {
                        BlackoutPistonSyncView {
                            client.finishBlackoutTask()
                        }
                    }
                }
            }
            // `safeAreaInset` reserves its own space above the task instead
            // of floating over it, so the bar can never cover part of a
            // landscape-cramped task's own top content.
            .safeAreaInset(edge: .top) {
                // No penalty for skipping the Black-out task (unlike the
                // turn-order minigame) — it's a shared emergency beat, not a
                // competitive race. See `GameSession.skipBlackoutTask(id:)`.
                if let startedAt = client.blackoutTaskStartedAt {
                    SkipCountdownBar(
                        deadline: startedAt.addingTimeInterval(GameSession.blackoutSkipGracePeriod),
                        buttonTitle: "SKIP",
                        onSkip: client.skipBlackoutTask
                    )
                }
            }
        }
    }

    private var roomSelectionView: some View {
        Group {
            if let secondsRemaining = roomFindingSecondsRemaining, let finding = client.myRoomFinding {
                RoomFindingView(room: lastChosenRoom, finding: finding, secondsRemaining: secondsRemaining)
            } else if client.isMyTurnToChooseRoom {
                RoomChoiceView(
                    takenRooms: Set(client.roomVisitLog.map(\.roomID)),
                    onChoose: { room in
                        lastChosenRoom = room
                        client.chooseRoom(room)
                    }
                )
            } else {
                waitingForTurnView
            }
        }
        .onChange(of: client.myRoomFinding) { _, finding in
            guard let finding else { return }
            // Accumulate distinct clues found across the whole game (not
            // just this round) — `lastChosenRoom` was set right before this
            // finding was requested, so it's still the room this finding
            // came from. Dedupe by equality so revisiting a room whose clue
            // hasn't moved (or seeing the same clue again after a Black-out
            // reshuffle) doesn't double-count toward the 3-clue vote gate.
            if case .clue(let clue) = finding, let room = lastChosenRoom,
               !collectedClues.contains(where: { $0.clue == clue }) {
                collectedClues.append((room: room, clue: clue))
            }
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
        LandscapeStatusView(icon: "hourglass") {
            Text(currentTurnPlayer.map { "\($0.nickname)'s turn…" } ?? "Waiting for the next turn…")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            Text("Watch the board on the Apple TV!")
                .font(.system(size: 16, design: .rounded))
                .foregroundStyle(.phoenixMuted)

            Text("Only 3 of the 9 rooms hide a clue")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.phoenixMuted.opacity(0.7))

            ProgressView()
                .tint(.white)
        }
    }

    private var votingView: some View {
        Group {
            if client.votingPlayerID == client.localPlayerID {
                AccusationPickerView(
                    wronglyAccusedSuspectIDs: wronglyAccusedSuspectIDs,
                    candidate: $accusationCandidate,
                    onConfirm: { suspect in client.castAccusation(suspectID: suspect.id) }
                )
            } else {
                lockedForVoteView
            }
        }
        .onChange(of: client.votingPlayerID) { _, votingPlayerID in
            guard votingPlayerID != nil, votingPlayerID != client.localPlayerID else { return }
            Haptics.notify(.warning)
        }
    }

    private var lockedForVoteView: some View {
        LandscapeStatusView(icon: "lock.fill", iconColor: .phoenixDestructive) {
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



    private func statusView(icon: String, title: String, subtitle: String?) -> some View {
        LandscapeStatusView(icon: icon) {
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

/// A slim countdown pill shown over an in-progress turn-order minigame or
/// Black-out task once the shared skip-grace-period window has started
/// (see `GameSession.minigameSkipGracePeriod`/`blackoutSkipGracePeriod`).
///
/// The host is the actual authority on when the grace period expires — it
/// auto-skips everyone still stuck once `deadline` passes (see
/// `HostConnectivityService`'s deadline tasks) — so this view is only the
/// on-screen countdown plus a manual way to bail out early. No local timer
/// state needed: `TimelineView` recomputes the remaining time from `deadline`
/// every tick, so this stays correct even if the view appears mid-countdown
/// (e.g. this player re-opens the app after someone else already finished).
private struct SkipCountdownBar: View {
    let deadline: Date
    let buttonTitle: String
    let onSkip: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(deadline.timeIntervalSince(context.date).rounded(.up)))

            HStack(spacing: 14) {
                Label("\(remaining)s", systemImage: "timer")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(remaining <= 5 ? Color.phoenixDestructive : Color.phoenixGold)
                    .contentTransition(.numericText())

                Spacer(minLength: 8)

                Button {
                    Haptics.notify(.warning)
                    onSkip()
                } label: {
                    Text(buttonTitle.uppercased())
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.phoenixDestructive.opacity(0.85), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 1))
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
    }
}

#Preview("Skip bar — iPhone landscape", traits: .landscapeRight) {
    ZStack {
        Color.phoenixBackground.ignoresSafeArea()
        VStack {
            SkipCountdownBar(
                deadline: Date().addingTimeInterval(12),
                buttonTitle: "SKIP (clue hidden)",
                onSkip: {}
            )
            Spacer()
        }
    }
    .preferredColorScheme(.dark)
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

/// One suspect's portrait card — shared by the notebook grid and the
/// accusation picker, which show the same suspect visuals (full portrait,
/// name plate in their case color, "RULED OUT" treatment once a wrong
/// accusation confirms them innocent) but differ in what the main tap does
/// (toggle exclude vs. pick as accusation candidate) and how the border
/// reacts (manual-exclude red vs. picker-selection highlight).
/// Not `private` — used from `NotebookView.swift`/`AccusationPickerView.swift`
/// (standalone files, extracted for previewability) as well as from
/// `ContentView` itself.
struct SuspectCardButton: View {
    let suspect: Suspect
    let isKnownInnocent: Bool
    let borderColor: Color
    let borderWidth: CGFloat
    let showXMark: Bool
    let width: CGFloat
    let portraitHeight: CGFloat
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                // Full portrait, never cropped — see `SuspectPortraitView`.
                SuspectPortraitView(suspect: suspect)
                    .frame(width: width, height: portraitHeight)
                    .grayscale(isKnownInnocent ? 1 : 0)
                    .opacity(isKnownInnocent || showXMark ? 0.3 : 1.0)

                Text(suspect.name.uppercased())
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(height: 42)
                    .frame(maxWidth: .infinity)
                    .background(suspect.color.color.opacity(0.8))
            }
            .frame(width: width)
            .background(Color.black)
            .overlay(Rectangle().strokeBorder(borderColor, lineWidth: borderWidth))
            .overlay {
                if isKnownInnocent {
                    VStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 34, weight: .black))
                        Text("RULED OUT")
                            .font(.system(size: 12, weight: .black, design: .monospaced))
                    }
                    .foregroundStyle(.white.opacity(0.85))
                } else if showXMark {
                    Image(systemName: "xmark")
                        .font(.system(size: 64, weight: .black))
                        .foregroundStyle(.red)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isKnownInnocent)
    }
}

// `homeScreen` reads no `client`/`@State` at all (confirmed: it's just
// "JOIN A ROOM"/"SETTINGS" over a video/gradient backdrop), and `isAtHome`
// defaults to `true`, so a bare `ContentView()` already previews it
// directly — no extraction/mock data needed, unlike every other phase.
#Preview("Home screen", traits: .landscapeRight) {
    ContentView()
        .preferredColorScheme(.dark)
}
