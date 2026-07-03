import Foundation
@preconcurrency import MultipeerConnectivity
import Observation

/// Runs on an iPhone controller: browses for the Apple TV host, connects,
/// and mirrors the lobby state (`players`, `phase`) the host broadcasts.
///
/// See `HostConnectivityService` for why this type is `NSObject` +
/// `@unchecked Sendable` rather than actor-isolated at the type level, and
/// why delegate callbacks hop to `@MainActor` via `Task`.
@Observable
public final class ClientConnectivityService: NSObject, @unchecked Sendable {
    /// Stable identity for this player, persisted across launches.
    public let localPlayerID: UUID

    @MainActor public private(set) var discoveredHosts: [MCPeerID] = []
    @MainActor public private(set) var connectionState: ClientConnectionState = .idle
    @MainActor public private(set) var players: [Player] = []
    @MainActor public private(set) var phase: GamePhase = .connecting
    @MainActor public private(set) var minigameFinishOrder: [UUID] = []
    @MainActor public private(set) var penalizedPlayerID: UUID?
    @MainActor public private(set) var turnOrder: [UUID] = []
    @MainActor public private(set) var currentTurnIndex: Int = 0
    @MainActor public private(set) var roomVisitLog: [RoomVisit] = []
    /// What this player found in the room they just chose. Only ever set by
    /// the private `.roomFinding` message — never inferred from
    /// `sessionState`, since the host never broadcasts clue content.
    @MainActor public private(set) var myRoomFinding: RoomFinding?
    /// Whether the host has let this player past the join-code gate. Only
    /// once `.accepted` may `join(nickname:)` be sent.
    @MainActor public private(set) var joinAuthorization: JoinAuthorization = .notRequested
    /// The player currently casting their vote, if any.
    @MainActor public private(set) var votingPlayerID: UUID?
    /// The most recently resolved vote, if any.
    @MainActor public private(set) var lastAccusation: Accusation?
    /// 1-indexed count of the current Minigame → Rooms → Notebook cycle.
    @MainActor public private(set) var roundNumber: Int = 1
    /// True while the current round is the Black-out round — voting is
    /// disabled while this holds.
    @MainActor public private(set) var isCurrentRoundBlackout: Bool = false
    /// When the current Black-out task began, for the on-screen (scenic
    /// only) stopwatch. `nil` outside `.blackoutTask`.
    @MainActor public private(set) var blackoutTaskStartedAt: Date?
    /// Players who have finished the Black-out emergency task this round.
    @MainActor public private(set) var blackoutTaskFinishedPlayerIDs: [UUID] = []
    /// Which emergency task plays during the Black-out round.
    @MainActor public private(set) var blackoutMinigame: BlackoutMinigame = .overvoltageWhack
    /// The team's target output for the `lightRegulator` task.
    @MainActor public private(set) var blackoutLightTarget: Double = 0
    /// The current average of every player's regulator slider, for the
    /// `lightRegulator` task.
    @MainActor public private(set) var blackoutLightAverage: Double = 0
    /// Which of the 13 turn-order minigames is being played this round.
    @MainActor public private(set) var turnMinigame: TurnMinigame = .numberMemory

    private var peerID: MCPeerID
    private var mcSession: MCSession
    private var browser: MCNearbyServiceBrowser
    /// Base display name a fresh `MCPeerID` is derived from on every
    /// `resetTransport()` — see that method for why the identity itself is
    /// regenerated rather than reused.
    private let displayNamePrefix: String
    /// The join code the host most recently accepted. `resetTransport()`
    /// mints a brand-new `MCPeerID` on every reconnect attempt, which means
    /// the host's `playerIDsByPeer` mapping for this player is gone even
    /// though `joinAuthorization` is still `.accepted` — silently resending
    /// `.requestToJoin` with this cached code (see the `.connected` case in
    /// `MCSessionDelegate`) re-establishes that mapping and cancels the
    /// host's disconnect grace-period removal, without bouncing the player
    /// back to the code-entry screen.
    @MainActor private var lastAcceptedJoinCode: String?
    /// The code most recently submitted via `requestToJoin(code:)`, kept
    /// around only until its `.joinResult` reply lands so an acceptance can
    /// be cached into `lastAcceptedJoinCode`.
    @MainActor private var pendingJoinCode: String?
    
    /// The MCPeerID of the host this client is attempting to connect to.
    /// In a MultipeerConnectivity session, all accepted peers form a mesh,
    /// meaning clients will receive state updates for other clients. We only
    /// care about the connection to the host.
    @MainActor private var hostPeerID: MCPeerID?

    @MainActor
    public init(displayName: String = UUID().uuidString, localPlayerID: UUID = PlayerIdentity.current()) {
        self.localPlayerID = localPlayerID
        self.displayNamePrefix = displayName
        let initialPeerID = MCPeerID(displayName: displayName)
        self.peerID = initialPeerID
        // See the matching comment on `HostConnectivityService` for why
        // `.none` instead of `.optional`/`.required`.
        self.mcSession = MCSession(peer: initialPeerID, securityIdentity: nil, encryptionPreference: .none)
        self.browser = MCNearbyServiceBrowser(peer: initialPeerID, serviceType: PeerService.type)
        super.init()
        mcSession.delegate = self
        browser.delegate = self
    }

    /// Tears down and rebuilds the peer identity, session, and browser from
    /// scratch. MultipeerConnectivity sessions can end up in a degraded
    /// state after a failed or abandoned connection attempt (a stale
    /// half-connected peer, an invite that timed out, …); starting every
    /// new browsing attempt on a completely fresh `MCPeerID`/`MCSession`
    /// avoids compounding that staleness across retries, rather than
    /// reusing the same session for the lifetime of the app.
    @MainActor
    private func resetTransport() {
        joinRequestRetryTask?.cancel()
        mcSession.disconnect()
        let freshPeerID = MCPeerID(displayName: displayNamePrefix)
        peerID = freshPeerID
        mcSession = MCSession(peer: freshPeerID, securityIdentity: nil, encryptionPreference: .none)
        browser = MCNearbyServiceBrowser(peer: freshPeerID, serviceType: PeerService.type)
        mcSession.delegate = self
        browser.delegate = self
    }

    /// Starts browsing for hosts advertising the game on the local network.
    /// Rebuilds the transport from scratch first (see `resetTransport()`),
    /// so every attempt — including a retry after a failed one — starts
    /// from a clean slate instead of a session that may have gone stale.
    ///
    /// No-ops when running inside an Xcode Previews canvas — see the matching
    /// guard on `HostConnectivityService.start()` for why.
    @MainActor
    public func startBrowsing() {
        guard !Self.isRunningInPreview else { return }
        resetTransport()
        discoveredHosts = []
        connectionState = .browsing
        browser.startBrowsingForPeers()
    }

    private static var isRunningInPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    public func stopBrowsing() {
        browser.stopBrowsingForPeers()
    }

    /// Invites a discovered host to connect.
    @MainActor
    public func connect(to host: MCPeerID) {
        hostPeerID = host
        connectionState = .connecting
        browser.invitePeer(host, to: mcSession, withContext: nil, timeout: 30)
    }

    @MainActor
    public func disconnect() {
        joinRequestRetryTask?.cancel()
        mcSession.disconnect()
    }

    // MARK: - Sending player actions

    /// Resends of the current `.requestToJoin`, in case the original send —
    /// or the host's `.joinResult` reply — gets dropped in transit. Cancelled
    /// as soon as a result comes in (or the view's own timeout fires), so it
    /// never races a settled `joinAuthorization`.
    @MainActor private var joinRequestRetryTask: Task<Void, Never>?

    /// Submits the host's join code. Only once accepted (see
    /// `joinAuthorization`) may `join(nickname:)` be sent. Resends the
    /// request a couple of times while waiting, since a single dropped
    /// packet (in either direction) would otherwise silently strand the
    /// player until the view's own timeout gives up.
    @MainActor
    public func requestToJoin(code: String) {
        joinAuthorization = .pending
        pendingJoinCode = code
        joinRequestRetryTask?.cancel()
        joinRequestRetryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for attempt in 0..<3 {
                guard self.joinAuthorization == .pending else { return }
                guard !self.mcSession.connectedPeers.isEmpty else {
                    // The transport itself is gone — retrying the message
                    // won't help, and waiting out the full 6s view timeout
                    // for a "No response" that can never resolve on its own
                    // just delays the player getting a "Retry" button. Fail
                    // fast instead.
                    print("ClientConnectivityService: no connected peer while joining — giving up early")
                    self.connectionState = .disconnected
                    return
                }
                self.send(.requestToJoin(id: self.localPlayerID, code: code))
                guard attempt < 2 else { return }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// Silently re-registers with the host after a transport reconnect,
    /// using the cached `lastAcceptedJoinCode` — unlike `requestToJoin(code:)`
    /// this does **not** touch `joinAuthorization` or start the retry loop,
    /// since the player already passed the code gate once this game and
    /// shouldn't be bounced back to the code-entry screen over a Wi-Fi
    /// hiccup. No-ops if this player was never accepted in the first place.
    @MainActor
    private func resendJoinAfterReconnect() {
        guard joinAuthorization == .accepted, let code = lastAcceptedJoinCode else { return }
        send(.requestToJoin(id: localPlayerID, code: code))
    }

    /// Called by the view if no `joinResult` arrives within its timeout
    /// window, so a lost message doesn't leave the UI spinning forever.
    /// No-ops if a result (or a newer request) has since come in.
    @MainActor
    public func timeoutJoinRequest() {
        guard joinAuthorization == .pending else { return }
        joinRequestRetryTask?.cancel()
        joinAuthorization = .timedOut
    }

    /// Sends the initial join message with the player's chosen nickname —
    /// only valid once `joinAuthorization == .accepted`. The host assigns
    /// the avatar.
    public func join(nickname: String) {
        send(.join(id: localPlayerID, nickname: nickname))
    }

    public func updateProfile(nickname: String) {
        send(.updateProfile(id: localPlayerID, nickname: nickname))
    }

    public func setReady(_ isReady: Bool) {
        send(.setReady(id: localPlayerID, isReady: isReady))
    }

    /// Sends that this player has finished the turn-order minigame.
    public func finishMinigame() {
        send(.finishMinigame(id: localPlayerID))
    }

    /// True once this player's `finishMinigame()` has been acknowledged by
    /// the host (i.e. it shows up in the broadcast `minigameFinishOrder`).
    @MainActor
    public var hasFinishedMinigame: Bool {
        minigameFinishOrder.contains(localPlayerID)
    }

    /// True once it's this player's turn to explore a room.
    @MainActor
    public var isMyTurnToChooseRoom: Bool {
        turnOrder.indices.contains(currentTurnIndex) && turnOrder[currentTurnIndex] == localPlayerID
    }

    /// Sends this player's room choice for their current turn. Clears any
    /// previous `myRoomFinding` first: `RoomFinding.empty`/`.hiddenByPenalty`
    /// carry no associated data, so if this turn's finding is equal to the
    /// last one (e.g. two empty rooms in a row), going through `nil` first
    /// guarantees the view's `onChange(of: client.myRoomFinding)` still
    /// fires and starts the reveal countdown.
    @MainActor
    public func chooseRoom(_ room: RoomID) {
        myRoomFinding = nil
        send(.chooseRoom(id: localPlayerID, room: room))
    }

    /// Requests to start casting the final-accusation vote.
    public func startVoting() {
        send(.startVoting(id: localPlayerID))
    }

    /// Casts this player's accusation — only valid while `votingPlayerID`
    /// (on the client) equals `localPlayerID`.
    public func castAccusation(suspectID: String) {
        send(.castAccusation(id: localPlayerID, suspectID: suspectID))
    }

    /// Sends that this player has finished the Black-out emergency task.
    public func finishBlackoutTask() {
        send(.finishBlackoutTask(id: localPlayerID))
    }

    /// Sends this player's regulator slider value for the `lightRegulator`
    /// black-out task.
    public func updateBlackoutLightValue(_ value: Double) {
        send(.updateBlackoutLightValue(id: localPlayerID, value: value))
    }

    /// Encodes and sends `message` to the host, logging failures instead of
    /// silently swallowing them the way a bare `try?` would. Multipeer sends
    /// do occasionally fail on real networks — surfacing that (even just to
    /// the console) makes flaky connections debuggable instead of looking
    /// like a message that was simply never sent.
    @discardableResult
    private func send(_ message: GameMessage) -> Bool {
        guard let peer = mcSession.connectedPeers.first else {
            print("ClientConnectivityService: cannot send \(message) — no connected peer")
            return false
        }
        do {
            let data = try message.encoded()
            try mcSession.send(data, toPeers: [peer], with: .reliable)
            return true
        } catch {
            print("ClientConnectivityService: failed to send \(message): \(error)")
            return false
        }
    }

    // MARK: - Message handling

    @MainActor
    private func handle(_ message: GameMessage) {
        switch message {
        case .sessionState(
            let players, let phase, let minigameFinishOrder, let penalizedPlayerID,
            let turnOrder, let currentTurnIndex, let roomVisitLog,
            let votingPlayerID, let lastAccusation,
            let roundNumber, let isCurrentRoundBlackout,
            let blackoutTaskStartedAt, let blackoutTaskFinishedPlayerIDs,
            let blackoutMinigame, let blackoutLightTarget, let blackoutLightAverage,
            let turnMinigame
        ):
            self.players = players
            self.phase = phase
            self.minigameFinishOrder = minigameFinishOrder
            self.penalizedPlayerID = penalizedPlayerID
            self.turnOrder = turnOrder
            self.currentTurnIndex = currentTurnIndex
            self.roomVisitLog = roomVisitLog
            self.votingPlayerID = votingPlayerID
            self.lastAccusation = lastAccusation
            self.roundNumber = roundNumber
            self.isCurrentRoundBlackout = isCurrentRoundBlackout
            self.blackoutTaskStartedAt = blackoutTaskStartedAt
            self.blackoutTaskFinishedPlayerIDs = blackoutTaskFinishedPlayerIDs
            self.blackoutMinigame = blackoutMinigame
            self.blackoutLightTarget = blackoutLightTarget
            self.blackoutLightAverage = blackoutLightAverage
            self.turnMinigame = turnMinigame

        case .startGame:
            phase = .starting

        case .roomFinding(let finding):
            myRoomFinding = finding

        case .joinResult(let accepted):
            joinRequestRetryTask?.cancel()
            joinAuthorization = accepted ? .accepted : .rejected
            if accepted {
                lastAcceptedJoinCode = pendingJoinCode
            }
            pendingJoinCode = nil

        case .kicked:
            connectionState = .disconnected
            mcSession.disconnect()

        case .requestToJoin, .join, .updateProfile, .setReady, .finishMinigame, .chooseRoom, .startVoting, .castAccusation, .finishBlackoutTask, .updateBlackoutLightValue:
            // Client-authored messages; the host never sends these back.
            break
        }
    }
}

extension ClientConnectivityService: MCSessionDelegate {
    public nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            guard peerID == self.hostPeerID else { return }
            
            switch state {
            case .connected:
                self.connectionState = .connected
                // No need to keep searching once we've actually connected —
                // also avoids the browser piling up stale peer sightings.
                self.browser.stopBrowsingForPeers()
                // `resetTransport()` mints a fresh MCPeerID on every attempt,
                // so a reconnect after a drop looks like a brand-new peer to
                // the host even though this player was already accepted —
                // silently re-register instead of waiting on the UI to do it.
                self.resendJoinAfterReconnect()
            case .connecting:
                self.connectionState = .connecting
            case .notConnected:
                self.joinRequestRetryTask?.cancel()
                if self.connectionState == .connected || self.connectionState == .connecting {
                    self.connectionState = .disconnected
                }
            @unknown default:
                break
            }
        }
    }

    public nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let message = try? GameMessage.decode(data) else { return }
        Task { @MainActor in
            self.handle(message)
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

extension ClientConnectivityService: MCNearbyServiceBrowserDelegate {
    public nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            // Dedupe by display name, not just MCPeerID identity: the same
            // physical host can occasionally be reported through more than
            // one non-equal MCPeerID (e.g. after a Bonjour re-advertise), and
            // since every host currently shares one hardcoded name, a player
            // has no way to tell such duplicates apart anyway.
            let alreadyListed = self.discoveredHosts.contains {
                $0 == peerID || $0.displayName == peerID.displayName
            }
            guard !alreadyListed else { return }
            self.discoveredHosts.append(peerID)
        }
    }

    public nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            self.discoveredHosts.removeAll { $0 == peerID || $0.displayName == peerID.displayName }
        }
    }
}
