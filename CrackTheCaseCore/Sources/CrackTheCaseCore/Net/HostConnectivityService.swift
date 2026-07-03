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
    public let session: GameSession

    /// Number of directly connected transport peers. Can momentarily differ
    /// from `session.players.count` around join/disconnect.
    @MainActor public private(set) var connectedPeerCount = 0

    private let peerID: MCPeerID
    private let mcSession: MCSession
    private let advertiser: MCNearbyServiceAdvertiser
    @MainActor private var playerIDsByPeer: [MCPeerID: UUID] = [:]
    /// Delayed `removePlayer` calls for players who just disconnected, so a
    /// brief network hiccup doesn't instantly erase their spot in the game —
    /// cancelled if they reconnect within the grace period.
    @MainActor private var pendingRemovals: [UUID: Task<Void, Never>] = [:]

    /// How long a disconnected player's roster entry survives before being
    /// removed for good, giving a transient drop time to reconnect.
    private static let disconnectGracePeriod: Duration = .seconds(20)

    @MainActor
    public init(displayName: String = "Phoenix Academy", session: GameSession = GameSession()) {
        self.session = session
        self.peerID = MCPeerID(displayName: displayName)
        // `.none`: this game exchanges no sensitive data (nicknames, avatar
        // picks, lobby state), so there's nothing worth encrypting — and on
        // real Wi-Fi networks `.optional` has been observed to let the
        // session *connect* successfully while the encrypted `.reliable`
        // data channel on top never actually stabilizes, so every
        // application message silently fails to send even though the
        // underlying MCSession reports `.connected`. `.none` skips that
        // negotiation entirely.
        self.mcSession = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .none)
        self.advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: PeerService.type)
        super.init()
        mcSession.delegate = self
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
    public func stop() {
        advertiser.stopAdvertisingPeer()
        mcSession.disconnect()
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
        session.beginMinigame()
        broadcastSessionState()
    }

    /// Transitions into `.roomSelection`, reusing the minigame arrival order
    /// as the turn order, and notifies every client.
    @MainActor
    public func beginRoomSelection() {
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

    /// Transitions into `.blackoutTask`, starting the emergency-task timer.
    @MainActor
    public func beginBlackoutTask() {
        session.beginBlackoutTask()
        broadcastSessionState()
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

        case .join(let id, let nickname):
            guard playerIDsByPeer[peer] == id else { return }
            let player = Player(id: id, nickname: nickname, avatar: session.nextAvatar())
            session.upsert(player)
            broadcastSessionState()

        case .updateProfile(let id, let nickname):
            guard var player = session.players.first(where: { $0.id == id }) else { return }
            player.nickname = nickname
            session.upsert(player)
            broadcastSessionState()

        case .setReady(let id, let isReady):
            guard var player = session.players.first(where: { $0.id == id }) else { return }
            player.isReady = isReady
            session.upsert(player)
            broadcastSessionState()

        case .finishMinigame(let id):
            session.recordMinigameFinish(id: id)
            broadcastSessionState()

        case .chooseRoom(let id, let room):
            guard let finding = session.recordRoomChoice(playerID: id, room: room) else { return }
            // Broadcast first so the board shows the avatar in the room right
            // away, then privately reveal what they found to them alone.
            broadcastSessionState()
            sendPrivate(.roomFinding(finding), to: id)

        case .startVoting(let id):
            guard session.startVoting(playerID: id) else { return }
            broadcastSessionState()

        case .castAccusation(let id, let suspectID):
            session.castAccusation(playerID: id, suspectID: suspectID)
            broadcastSessionState()

        case .finishBlackoutTask(let id):
            session.recordBlackoutTaskFinish(id: id)
            broadcastSessionState()

        case .updateBlackoutLightValue(let id, let value):
            session.updateBlackoutLightValue(playerID: id, value: value)
            broadcastSessionState()

        case .sessionState, .startGame, .roomFinding, .joinResult, .kicked:
            // Host-authored messages; a well-behaved client never sends these.
            break
        }
    }

    @MainActor
    private func handleDisconnect(of peer: MCPeerID) {
        guard let playerID = playerIDsByPeer.removeValue(forKey: peer) else { return }

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
                penalizedPlayerID: session.penalizedPlayerID,
                turnOrder: session.turnOrder,
                currentTurnIndex: session.currentTurnIndex,
                roomVisitLog: session.roomVisitLog,
                votingPlayerID: session.votingPlayerID,
                lastAccusation: session.lastAccusation,
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

    private func broadcast(_ message: GameMessage) {
        send(message, to: mcSession.connectedPeers)
    }

    /// Sends a message to a single player only, e.g. their private
    /// `roomFinding`. No-ops if that player isn't currently connected.
    @MainActor
    private func sendPrivate(_ message: GameMessage, to playerID: UUID) {
        guard let peer = playerIDsByPeer.first(where: { $0.value == playerID })?.key else { return }
        send(message, to: [peer])
    }

    /// Encodes and sends `message` to `peers`, logging failures instead of
    /// silently swallowing them the way a bare `try?` would. Multipeer
    /// sends do occasionally fail on real networks — surfacing that (even
    /// just to the console) makes flaky connections debuggable instead of
    /// looking like a message that was simply never sent.
    @discardableResult
    private func send(_ message: GameMessage, to peers: [MCPeerID]) -> Bool {
        guard !peers.isEmpty else { return false }
        // Unambiguous diagnostic if a peer we're about to reply to (e.g. a
        // `.joinResult` for a `.requestToJoin`) has already dropped out of
        // the session — the send below will throw, but this pinpoints
        // *which* peer and *when*, rather than leaving it to be inferred
        // from the thrown error alone.
        let stalePeers = peers.filter { !mcSession.connectedPeers.contains($0) }
        if !stalePeers.isEmpty {
            print("HostConnectivityService: sending \(message) to peer(s) no longer in connectedPeers: \(stalePeers.map(\.displayName))")
        }
        do {
            let data = try message.encoded()
            try mcSession.send(data, toPeers: peers, with: .reliable)
            return true
        } catch {
            print("HostConnectivityService: failed to send \(message) to \(peers.map(\.displayName)): \(error)")
            return false
        }
    }
}

extension HostConnectivityService: MCSessionDelegate {
    public nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            self.connectedPeerCount = session.connectedPeers.count
            if state == .notConnected {
                self.handleDisconnect(of: peerID)
            }
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
        invitationHandler(true, mcSession)
    }
}
