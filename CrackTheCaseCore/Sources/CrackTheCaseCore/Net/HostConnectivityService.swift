import Foundation
@preconcurrency import MultipeerConnectivity
import Observation

/// Runs on the Apple TV: advertises the game session over the local network,
/// accepts connecting iPhones, and keeps `session` (the `GameSession`) in
/// sync as clients join, update their profile, or toggle ready.
///
/// Every mutation is followed by a `lobbyState` broadcast so every client
/// mirrors the same roster. The class is not actor-isolated at the type
/// level (MultipeerConnectivity's delegate protocols are synchronous and
/// called off the main thread); instead the mutating methods are individually
/// `@MainActor` and delegate callbacks hop over via `Task { @MainActor in }`.
/// `@unchecked Sendable` reflects that we take on that synchronization by hand.
@Observable
public final class HostConnectivityService: NSObject, @unchecked Sendable {
    /// Reassigned wholesale by `startNewGame()` to get a fresh room (new join
    /// code, empty roster) without touching `peerID`/`advertiser` — see that
    /// method's doc comment for why the transport identity must stay put.
    /// `@Observable` tracks the reassignment itself, so views reading
    /// `host.session` still update live.
    public private(set) var session: GameSession

    /// Number of directly connected transport peers. Can momentarily differ
    /// from `session.players.count` around join/disconnect.
    @MainActor public private(set) var connectedPeerCount = 0

    private let peerID: MCPeerID
    @MainActor private var clientSessions: [MCPeerID: MCSession] = [:]
    private let advertiser: MCNearbyServiceAdvertiser
    @MainActor private var playerIDsByPeer: [MCPeerID: UUID] = [:]
    /// Findings collected as each player picks their room this round, held
    /// back instead of sent immediately so every player reads their clue at
    /// the same time once the whole turn order has gone — see `.chooseRoom`.
    @MainActor private var pendingRoomFindings: [UUID: RoomFinding] = [:]
    /// Delayed `removePlayer` calls for players who just disconnected, so a
    /// brief network hiccup doesn't instantly erase their spot in the game —
    /// cancelled if they reconnect within the grace period.
    @MainActor private var pendingRemovals: [UUID: Task<Void, Never>] = [:]
    /// Armed the moment the first player finishes this round's turn-order
    /// minigame; once `GameSession.minigameSkipGracePeriod` elapses, whoever
    /// still hasn't finished gets auto-skipped (with the same penalty as
    /// pressing "Skip" themselves) so one stuck player can't stall the game
    /// forever. Cancelled once everyone's finished, the round moves on, or a
    /// stuck player leaves and drops the group below the finish count.
    @MainActor private var minigameDeadlineTask: Task<Void, Never>?
    /// Same idea as `minigameDeadlineTask`, but for the Black-out emergency
    /// task — armed in `beginBlackoutTask()` instead of on first finish,
    /// and its skips carry no penalty (see `GameSession.skipBlackoutTask(id:)`).
    @MainActor private var blackoutDeadlineTask: Task<Void, Never>?

    /// How long a disconnected player's roster entry survives before being
    /// removed for good, giving a transient drop time to reconnect.
    private static let disconnectGracePeriod: Duration = .seconds(20)

    @MainActor
    public init(displayName: String = "Phoenix Academy", session: GameSession = GameSession()) {
        self.session = session
        self.peerID = MCPeerID(displayName: displayName)
        self.advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: PeerService.type)
        super.init()
        advertiser.delegate = self
    }

    /// Starts advertising the session so nearby clients can discover it.
    ///
    /// No-ops when running inside an Xcode Previews canvas: `#Preview` runs
    /// this same `ContentView` code in a live simulator process, and without
    /// this guard every canvas render leaves behind another real advertiser
    /// that a physical client can discover as a duplicate, ghost "Phoenix
    /// Academy" host.
    public func start() {
        guard !Self.isRunningInPreview else { return }
        advertiser.startAdvertisingPeer()
    }

    private static var isRunningInPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    /// Stops advertising and disconnects every connected client. Only meant
    /// for an explicit, intentional teardown — see `pauseAdvertising()` for
    /// the much more common "briefly backgrounded" case, which must **not**
    /// drop live players.
    ///
    /// Broadcasts `.kicked` *before* disconnecting: without it, a client's
    /// transport briefly looks the same as a transient Wi-Fi hiccup, so
    /// `ClientConnectivityService` would just silently try to reconnect —
    /// including resending its cached join code — into a session that no
    /// longer exists, stranding the phone on a spinner instead of dropping
    /// it back to the "find a host" screen.
    @MainActor
    public func stop() {
        advertiser.stopAdvertisingPeer()
        for session in clientSessions.values {
            session.disconnect()
        }
        clientSessions.removeAll()
        playerIDsByPeer.removeAll()
        for task in pendingRemovals.values {
            task.cancel()
        }
        pendingRemovals.removeAll()
        pendingRoomFindings.removeAll()
        minigameDeadlineTask?.cancel()
        minigameDeadlineTask = nil
        blackoutDeadlineTask?.cancel()
        blackoutDeadlineTask = nil
    }

    /// Starts a brand-new room in place — a fresh join code and an empty
    /// roster — for the tvOS "New Game" button, **without** touching
    /// `peerID`/`advertiser`.
    ///
    /// This used to be done by throwing away the whole
    /// `HostConnectivityService` and constructing a new one, which also mints
    /// a new `MCPeerID`. That broke discovery: every host advertises under
    /// the same hardcoded display name ("Phoenix Academy"), and
    /// `ClientConnectivityService` dedupes discovered hosts *by display
    /// name*, not peer identity (see its `foundPeer` delegate method) — so a
    /// phone that had already seen the previous game's host held onto that
    /// now-dead peer sighting and either tried inviting it (stuck
    /// "Connecting…" forever) or ignored the new peer as a duplicate (stuck
    /// "Scanning…"). Keeping one stable `MCPeerID`/advertiser for the whole
    /// app lifetime and only swapping out `session` avoids that entirely.
    @MainActor
    public func startNewGame() {
        session = GameSession()
        //playerIDsByPeer.removeAll()
        /*
        for task in pendingRemovals.values {
            task.cancel()
        }
        pendingRemovals.removeAll()
        pendingRoomFindings.removeAll()
        minigameDeadlineTask?.cancel()
        minigameDeadlineTask = nil
        blackoutDeadlineTask?.cancel()
        blackoutDeadlineTask = nil*/
        /*for clientSession in clientSessions.values {
            clientSession.disconnect()
        }*/
        //clientSessions.removeAll()
    }

    /// Stops advertising (so no new "ghost" host lingers) without touching
    /// any already-connected player. Use this for transient background
    /// transitions (e.g. a Siri Remote Home-button tap) that aren't an
    /// intentional end to the game — `stop()` would otherwise disconnect
    /// every player over something that isn't really a quit.
    public func pauseAdvertising() {
        advertiser.stopAdvertisingPeer()
    }

    /// Transitions the lobby into `.starting` and notifies every client, if
    /// `GameSession.canStart` currently holds.
    @MainActor
    public func requestStartGame() {
        guard session.canStart else { return }
        session.phase = .starting
        broadcast(.startGame)
        broadcastSessionState()
    }

    /// Shows the introductory story video (or its placeholder) on the tvOS
    /// board.
    @MainActor
    public func beginIntroVideo() {
        session.phase = .introVideo
        broadcastSessionState()
    }

    /// Shows the rulebook on the tvOS board.
    @MainActor
    public func beginRules() {
        session.phase = .rules
        broadcastSessionState()
    }

    /// Transitions into `.minigame`, clearing any previous round's arrival
    /// order, and notifies every client.
    @MainActor
    public func beginMinigame() {
        minigameDeadlineTask?.cancel()
        minigameDeadlineTask = nil
        blackoutDeadlineTask?.cancel()
        blackoutDeadlineTask = nil
        session.beginMinigame()
        broadcastSessionState()
    }

    /// Transitions into `.roomSelection`, reusing the minigame arrival order
    /// as the turn order, and notifies every client.
    @MainActor
    public func beginRoomSelection() {
        minigameDeadlineTask?.cancel()
        minigameDeadlineTask = nil
        session.beginRoomSelection()
        broadcastSessionState()
    }

    /// Advances to the next player's turn once the current turn holder's
    /// reading window has elapsed, and notifies every client.
    @MainActor
    public func advanceRoomTurn() {
        session.advanceRoomTurn()
        broadcastSessionState()
    }

    /// Shows the suspects on the tvOS board; each player's notebook is their
    /// own local business from here on, never synced through the host.
    @MainActor
    public func beginNotebook() {
        session.phase = .notebook
        broadcastSessionState()
    }

    /// Starts the next round from the TV's "Next round" button: either
    /// straight back into `.minigame`, or into the Black-out narrative beat
    /// if this is the designated round.
    @MainActor
    public func beginNextRound() {
        session.beginNextRound()
        broadcastSessionState()
    }

    /// Transitions into `.blackoutTask`, starting the emergency-task timer,
    /// and arms the skip-grace-period deadline: after
    /// `GameSession.blackoutSkipGracePeriod`, anyone still stuck is
    /// auto-skipped (no penalty — see `GameSession.skipBlackoutTask(id:)`)
    /// so the round can't stall forever on one player.
    @MainActor
    public func beginBlackoutTask() {
        session.beginBlackoutTask()
        broadcastSessionState()

        blackoutDeadlineTask?.cancel()
        blackoutDeadlineTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(GameSession.blackoutSkipGracePeriod))
            guard let self, !Task.isCancelled, self.session.phase == .blackoutTask else { return }
            for player in self.session.players where !self.session.blackoutTaskFinishedPlayerIDs.contains(player.id) {
                self.session.skipBlackoutTask(id: player.id)
            }
            self.broadcastSessionState()
        }
    }

    /// Starts a fresh game with the same connected players from the TV's
    /// "Play Again" button on the victory screen.
    @MainActor
    public func playAgain() {
        session.resetToLobby()
        broadcastSessionState()
    }

    /// Returns to the lobby from the TV's "Back to lobby" button on the
    /// `.notEnoughPlayers` interruption screen.
    @MainActor
    public func acknowledgeNotEnoughPlayers() {
        session.resetToLobby()
        broadcastSessionState()
    }

    // MARK: - Message handling

    @MainActor
    private func handle(_ message: GameMessage, from peer: MCPeerID) {
        switch message {
        case .requestToJoin(let id, let code):
            let accepted = code == session.joinCode
            // Only map the peer once the code checks out, so a `.join` from
            // someone who never passed this gate is silently ignored below.
            if accepted {
                // If the player reconnected with a new MCPeerID, disconnect their old ghost session immediately
                // so it doesn't leak or trigger a spurious .notConnected disconnect later.
                let oldPeers = playerIDsByPeer.filter { $0.value == id && $0.key != peer }.map { $0.key }
                for oldPeer in oldPeers {
                    playerIDsByPeer.removeValue(forKey: oldPeer)
                    if let oldSession = clientSessions.removeValue(forKey: oldPeer) {
                        oldSession.disconnect()
                    }
                }
                
                playerIDsByPeer[peer] = id
                // They're back within the grace period: keep their roster
                // spot instead of letting the scheduled removal fire.
                pendingRemovals[id]?.cancel()
                pendingRemovals.removeValue(forKey: id)
            }
            // Reply directly to `peer` (rather than `sendPrivate`, which
            // looks the peer up via `playerIDsByPeer`): on rejection that
            // mapping was deliberately never created.
            send(.joinResult(accepted: accepted), to: [peer])
            
            // If they are re-joining mid-game, they missed session state updates.
            // Broadcasting it brings them (and everyone else) back in sync.
            if accepted {
                broadcastSessionState()
            }

        case .join(let id, let nickname, let avatar):
            guard playerIDsByPeer[peer] == id else { return }
            // Joining is only meaningful pre-game: the whole flow (turn
            // order, room clues, notebook) assumes a fixed roster once the
            // lobby closes, and a client that joined mid-round would never
            // have gone through `.lobby` in the first place — its own
            // sessionState would jump straight into whatever phase is
            // already running, and it'd silently count toward
            // `players.count` without ever appearing in this round's
            // `minigameFinishOrder`/`blackoutTaskFinishedPlayerIDs`,
            // stalling the round forever waiting for a finish that can't
            // come. Simplest fix: a join outside `.lobby` is ignored.
            guard session.phase == .lobby else { return }
            let trimmedNickname = nickname.trimmingCharacters(in: .whitespaces)
            guard !trimmedNickname.isEmpty else { return }
            // If the requested avatar is taken or missing, we could fallback,
            // but for a simple local game we can just allow the chosen one or fallback if nil.
            let assignedAvatar = avatar ?? session.nextAvatar()
            let player = Player(id: id, nickname: trimmedNickname, avatar: assignedAvatar)
            session.upsert(player)
            broadcastSessionState()

        case .updateProfile(let id, let nickname, let avatar):
            guard var player = session.players.first(where: { $0.id == id }) else { return }
            let trimmedNickname = nickname.trimmingCharacters(in: .whitespaces)
            guard !trimmedNickname.isEmpty else { return }
            player.nickname = trimmedNickname
            if let newAvatar = avatar {
                player.avatar = newAvatar
            }
            session.upsert(player)
            broadcastSessionState()

        case .setReady(let id, let isReady):
            guard var player = session.players.first(where: { $0.id == id }) else { return }
            player.isReady = isReady
            session.upsert(player)
            broadcastSessionState()

        case .finishMinigame(let id):
            let wasFirstFinish = session.minigameFirstFinishAt == nil
            session.recordMinigameFinish(id: id)
            if wasFirstFinish, session.minigameFirstFinishAt != nil {
                armMinigameDeadline()
            }
            broadcastSessionState()

        case .skipMinigame(let id):
            let wasFirstFinish = session.minigameFirstFinishAt == nil
            session.skipMinigame(id: id)
            if wasFirstFinish, session.minigameFirstFinishAt != nil {
                armMinigameDeadline()
            }
            broadcastSessionState()

        case .chooseRoom(let id, let room):
            guard let finding = session.recordRoomChoice(playerID: id, room: room) else { return }
            pendingRoomFindings[id] = finding
            // Advance the turn immediately — no per-turn waiting — so
            // everyone picks in quick succession. The board fills in live via
            // this broadcast, but nobody's clue is revealed yet: every
            // finding is held back and sent together once the whole turn
            // order has gone, so all players read their own clue at the
            // same time.
            session.advanceRoomTurn()
            broadcastSessionState()
            flushRoomFindingsIfComplete()

        case .startVoting(let id):
            guard session.startVoting(playerID: id) else { return }
            broadcastSessionState()

        case .castAccusation(let id, let suspectID):
            session.castAccusation(playerID: id, suspectID: suspectID)
            broadcastSessionState()

        case .finishBlackoutTask(let id):
            session.recordBlackoutTaskFinish(id: id)
            broadcastSessionState()

        case .skipBlackoutTask(let id):
            session.skipBlackoutTask(id: id)
            broadcastSessionState()

        case .updateBlackoutLightValue(let id, let value):
            session.updateBlackoutLightValue(playerID: id, value: value)
            broadcastSessionState()

        case .sessionState, .startGame, .roomFinding, .joinResult, .kicked:
            // Host-authored messages; a well-behaved client never sends these.
            break
        }
    }

    /// Starts the countdown that auto-skips (with penalty) anyone still
    /// stuck on this round's turn-order minigame once
    /// `GameSession.minigameSkipGracePeriod` elapses since the first
    /// finisher. Called the moment `session.minigameFirstFinishAt` first
    /// gets set, from either `.finishMinigame` or `.skipMinigame`.
    @MainActor
    private func armMinigameDeadline() {
        minigameDeadlineTask?.cancel()
        minigameDeadlineTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(GameSession.minigameSkipGracePeriod))
            guard let self, !Task.isCancelled, self.session.phase == .minigame else { return }
            for player in self.session.players where !self.session.minigameFinishOrder.contains(player.id) {
                self.session.skipMinigame(id: player.id)
            }
            self.broadcastSessionState()
        }
    }

    @MainActor
    private func handleDisconnect(of peer: MCPeerID) {
        guard let playerID = playerIDsByPeer.removeValue(forKey: peer) else { return }
        
        // If they already reconnected using a new MCPeerID, they are still in the game.
        // We shouldn't kick them out just because their old ghost session finally timed out.
        if playerIDsByPeer.values.contains(playerID) {
            return
        }

        guard session.phase != .lobby else {
            // Pre-game there's nothing at stake in reconnecting quickly, so
            // reflect the drop on the board immediately — matches what
            // players actually expect to see happen right away.
            session.removePlayer(id: playerID)
            broadcastSessionState()
            // Best-effort: `peer` is almost always already unreachable at
            // this point (that's why it's being removed), but this closes
            // the gap where `.kicked` was defined and handled by the client
            // yet never actually sent by the host.
            send(.kicked, to: [peer])
            return
        }

        // Mid-game, don't erase their roster spot immediately: a brief drop
        // (phone locking, a Wi-Fi hiccup) shouldn't cost them their turn or
        // progress if they reconnect within the grace period.
        pendingRemovals[playerID]?.cancel()
        pendingRemovals[playerID] = Task { @MainActor in
            try? await Task.sleep(for: Self.disconnectGracePeriod)
            guard !Task.isCancelled else { return }
            session.removePlayer(id: playerID)
            pendingRemovals.removeValue(forKey: playerID)
            broadcastSessionState()
            // The player who just aged out could have been the last turn
            // holder room selection was waiting on — see
            // `flushRoomFindingsIfComplete`'s doc comment for why this
            // matters as much as the `.chooseRoom` call site.
            flushRoomFindingsIfComplete()
            send(.kicked, to: [peer])
        }
    }

    @MainActor
    private func broadcastSessionState() {
        broadcast(
            .sessionState(
                players: session.players,
                phase: session.phase,
                minigameFinishOrder: session.minigameFinishOrder,
                minigameFirstFinishAt: session.minigameFirstFinishAt,
                penalizedPlayerIDs: session.penalizedPlayerIDs,
                turnOrder: session.turnOrder,
                currentTurnIndex: session.currentTurnIndex,
                roomVisitLog: session.roomVisitLog,
                votingPlayerID: session.votingPlayerID,
                lastAccusation: session.lastAccusation,
                failedAccusationPlayerIDs: session.failedAccusationPlayerIDs,
                votingBanRoundNumbers: session.votingBanRoundNumbers,
                roundNumber: session.roundNumber,
                isCurrentRoundBlackout: session.isCurrentRoundBlackout,
                blackoutTaskStartedAt: session.blackoutTaskStartedAt,
                blackoutTaskFinishedPlayerIDs: session.blackoutTaskFinishedPlayerIDs,
                blackoutMinigame: session.blackoutMinigame,
                blackoutLightTarget: session.blackoutLightTarget,
                blackoutLightAverage: session.blackoutLightAverage,
                turnMinigame: session.turnMinigame
            )
        )
    }

    @MainActor
    private func broadcast(_ message: GameMessage) {
        let peers = clientSessions.compactMap { (peer, session) -> MCPeerID? in
            !session.connectedPeers.isEmpty ? peer : nil
        }
        send(message, to: peers)
    }

    /// Sends a message to a single player only, e.g. their private
    /// `roomFinding`. No-ops if that player isn't currently connected.
    @MainActor
    private func sendPrivate(_ message: GameMessage, to playerID: UUID) {
        guard let peer = playerIDsByPeer.first(where: { $0.value == playerID })?.key else { return }
        send(message, to: [peer])
    }

    /// Delivers every held-back `roomFinding` once the whole turn order has
    /// gone — called both right after a `.chooseRoom` (the common case) and
    /// from `handleDisconnect`'s delayed removal. That second call site
    /// matters: room selection can also complete because the *last*
    /// remaining turn holder disconnects rather than actually choosing a
    /// room (`removePlayer` shrinks `turnOrder`), and without this the
    /// findings collected from everyone who already went this round would
    /// never be sent — silently stranding the round in `.roomSelection`
    /// forever, since nothing else ever flushes `pendingRoomFindings`.
    @MainActor
    private func flushRoomFindingsIfComplete() {
        guard session.isRoomSelectionComplete else { return }
        for (playerID, pendingFinding) in pendingRoomFindings {
            sendPrivate(.roomFinding(pendingFinding), to: playerID)
        }
        pendingRoomFindings.removeAll()
    }

    /// Encodes and sends `message` to `peers`, logging failures instead of
    /// silently swallowing them the way a bare `try?` would. Multipeer
    /// sends do occasionally fail on real networks — surfacing that (even
    /// just to the console) makes flaky connections debuggable instead of
    /// looking like a message that was simply never sent.
    @MainActor
    @discardableResult
    private func send(_ message: GameMessage, to peers: [MCPeerID]) -> Bool {
        guard !peers.isEmpty else { return false }
        var overallSuccess = true
        do {
            let data = try message.encoded()
            for peer in peers {
                guard let session = clientSessions[peer] else { continue }
                let targetPeers = session.connectedPeers
                if targetPeers.isEmpty {
                    print("HostConnectivityService: sending \(message) to peer no longer in connectedPeers: \(peer.displayName)")
                    continue
                }
                do {
                    try session.send(data, toPeers: targetPeers, with: .reliable)
                } catch {
                    print("HostConnectivityService: failed to send \(message) to \(peer.displayName): \(error)")
                    overallSuccess = false
                }
            }
            return overallSuccess
        } catch {
            return false
        }
    }
}

extension HostConnectivityService: MCSessionDelegate {
    public nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            if state == .notConnected {
                // Find the entry that has this session to safely remove it,
                // instead of relying on exact MCPeerID equality which can fail.
                if let key = self.clientSessions.first(where: { $0.value === session })?.key {
                    self.clientSessions.removeValue(forKey: key)
                    self.handleDisconnect(of: key)
                }
            }
            var count = 0
            for (_, s) in self.clientSessions {
                if !s.connectedPeers.isEmpty { count += 1 }
            }
            self.connectedPeerCount = count
        }
    }

    public nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let message = try? GameMessage.decode(data) else { return }
        Task { @MainActor in
            self.handle(message, from: peerID)
        }
    }

    public nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // Not used by this game.
    }

    public nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        // Not used by this game.
    }

    public nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: (any Error)?) {
        // Not used by this game.
    }
}

extension HostConnectivityService: MCNearbyServiceAdvertiserDelegate {
    public nonisolated func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        // Create a new session specifically for this peer to force a star topology.
        // This prevents the unstable mesh network formation that used to cause
        // players to drop when >2 clients connect — that instability is now
        // fully addressed by the dedicated per-peer session below, so it no
        // longer requires `encryptionPreference: .none`. `.required` instead:
        // real-world reports (and this project's own repeated "stuck on
        // Connecting" / AWDL `SO_ERROR 60` timeouts) point at unencrypted
        // MCSessions being *less* reliable at establishing the underlying
        // peer-to-peer radio link on recent iOS/tvOS, not more — the
        // encryption handshake seems to help stabilize the AWDL link rather
        // than just sitting on top of an already-stable one. Must match
        // `ClientConnectivityService`'s own `encryptionPreference`, or the two
        // sides' sessions fail to negotiate at all.
        let newSession = MCSession(peer: self.peerID, securityIdentity: nil, encryptionPreference: .required)
        newSession.delegate = self

        Task { @MainActor in
            if let old = self.clientSessions[peerID] {
                old.disconnect()
            }
            self.clientSessions[peerID] = newSession
        }

        invitationHandler(true, newSession)
    }
}
