import Foundation
import MultipeerConnectivity
import Combine

class LightSessionManager: NSObject, ObservableObject {
    private let serviceType = "light-coop"
    private var myPeerID: MCPeerID
    private var serviceAdvertiser: MCNearbyServiceAdvertiser
    private var serviceBrowser: MCNearbyServiceBrowser
    private var session: MCSession
    
    private var gameTimer: Timer?
    
    private var isHost: Bool {
        guard let firstPeer = session.connectedPeers.sorted(by: { $0.displayName < $1.displayName }).first else { return true }
        return myPeerID.displayName <= firstPeer.displayName
    }
    
    @Published var playersLight: [String: Double] = [:]
    @Published var targetLight: Double = 50.0
    @Published var currentAverage: Double = 0.0
    @Published var isBlackoutFixed: Bool = false
    
    @Published var timeRemaining: Int = 120
    @Published var isGameOver: Bool = false
    
    init(displayName: String) {
        self.myPeerID = MCPeerID(displayName: displayName)
        self.session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        self.serviceAdvertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: serviceType)
        self.serviceBrowser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        
        super.init()
        
        self.session.delegate = self
        self.serviceAdvertiser.delegate = self
        self.serviceBrowser.delegate = self
        
        if isHost {
            self.targetLight = Double(Int.random(in: 40...85))
            startGlobalTimer()
        }
        
        self.serviceAdvertiser.startAdvertisingPeer()
        self.serviceBrowser.startBrowsingForPeers()
        
        self.playersLight[myPeerID.displayName] = 0.0
    }
    
    private func startGlobalTimer() {
        gameTimer?.invalidate()
        gameTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            if self.isBlackoutFixed || self.isGameOver { return }
            
            let penalty = self.isBlackoutFixed ? 1 : 10
            
            DispatchQueue.main.async {
                self.timeRemaining = max(0, self.timeRemaining - penalty)
                self.sendTimerUpdate()
                
                if self.timeRemaining <= 0 {
                    self.isGameOver = true
                    self.sendGameOver()
                }
            }
        }
    }
    
    func updateMyLightValue(_ value: Double) {
        DispatchQueue.main.async {
            self.playersLight[self.myPeerID.displayName] = value
            self.recalculateAverage()
        }
        
        let message: [String: Any] = ["type": "lightValue", "player": myPeerID.displayName, "value": value]
        sendData(message)
    }
    
    func syncGameConfiguration() {
        guard isHost else { return }
        let msg: [String: Any] = [
            "type": "gameConfig",
            "target": targetLight,
            "time": timeRemaining
        ]
        sendData(msg)
    }
    
    private func sendTimerUpdate() {
        let msg: [String: Any] = ["type": "timerUpdate", "time": timeRemaining]
        sendData(msg)
    }
    
    private func sendGameOver() {
        let msg: [String: Any] = ["type": "gameOver"]
        sendData(msg)
    }
    
    private func recalculateAverage() {
        let total = playersLight.values.reduce(0, +)
        let count = max(1, playersLight.count)
        self.currentAverage = total / Double(count)
        
        if isHost {
            checkVictoryCondition()
        }
    }
    
    private func checkVictoryCondition() {
        if abs(currentAverage - targetLight) < 1.0 && !isBlackoutFixed && !isGameOver {
            isBlackoutFixed = true
            gameTimer?.invalidate()
            let winMsg: [String: Any] = ["type": "victory"]
            sendData(winMsg)
        }
    }
    
    private func sendData(_ dictionary: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dictionary, options: []) else { return }
        guard !session.connectedPeers.isEmpty else { return }
        try? session.send(data, toPeers: session.connectedPeers, with: .reliable)
    }
    
    deinit {
        gameTimer?.invalidate()
    }
}

extension LightSessionManager: MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        
    }
    
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else { return }
        
        DispatchQueue.main.async {
            if let type = json["type"] as? String {
                switch type {
                case "gameConfig":
                    if let target = json["target"] as? Double { self.targetLight = target }
                    if let time = json["time"] as? Int { self.timeRemaining = time }
                case "timerUpdate":
                    if let time = json["time"] as? Int { self.timeRemaining = time }
                case "lightValue":
                    if let player = json["player"] as? String, let value = json["value"] as? Double {
                        self.playersLight[player] = value
                        self.recalculateAverage()
                    }
                case "victory":
                    self.isBlackoutFixed = true
                case "gameOver":
                    self.isGameOver = true
                default:
                    break
                }
            }
        }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        browser.invitePeer(peerID, to: self.session, withContext: nil, timeout: 10)
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {}
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, self.session)
    }
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {}
    
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            if state == .connected {
                self.playersLight[peerID.displayName] = 0.0
                self.syncGameConfiguration()
            } else if state == .notConnected {
                self.playersLight.removeValue(forKey: peerID.displayName)
                self.recalculateAverage()
            }
        }
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
