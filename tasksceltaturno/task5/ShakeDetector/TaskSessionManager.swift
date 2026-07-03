import Foundation
import MultipeerConnectivity
import Combine

class TaskSessionManager: NSObject, ObservableObject {
    private let serviceType = "battery-shake"
    private var myPeerID: MCPeerID
    private var serviceAdvertiser: MCNearbyServiceAdvertiser
    private var serviceBrowser: MCNearbyServiceBrowser
    private var session: MCSession
    
    private var isHost: Bool {
        guard let firstPeer = session.connectedPeers.sorted(by: { $0.displayName < $1.displayName }).first else { return true }
        return myPeerID.displayName <= firstPeer.displayName
    }
    
    @Published var playersProgress: [String: CGFloat] = [:]
    @Published var podium: [String] = []
    @Published var isTaskCompleted: Bool = false
    
    // Percentuale di partenza sincronizzata per tutti
    @Published var startingProgress: CGFloat = 0.0
    
    init(displayName: String) {
        self.myPeerID = MCPeerID(displayName: displayName)
        self.session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        self.serviceAdvertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: serviceType)
        self.serviceBrowser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        
        super.init()
        
        self.session.delegate = self
        self.serviceAdvertiser.delegate = self
        self.serviceBrowser.delegate = self
        
        // Se sono l'host iniziale, scelgo un punto di partenza casuale a scaglioni (es. 0%, 20%, 40%, 60%)
        let availableStarts: [CGFloat] = [0.0, 0.20, 0.40, 0.60]
        self.startingProgress = availableStarts.randomElement() ?? 0.0
        
        self.serviceAdvertiser.startAdvertisingPeer()
        self.serviceBrowser.startBrowsingForPeers()
        
        self.playersProgress[myPeerID.displayName] = self.startingProgress
    }
    
    func updateMyProgress(_ progress: CGFloat) {
        DispatchQueue.main.async {
            self.playersProgress[self.myPeerID.displayName] = progress
            if progress >= 1.0 {
                self.reportExecutionFinished(player: self.myPeerID.displayName)
            }
        }
        
        let message: [String: Any] = ["type": "progress", "player": myPeerID.displayName, "value": progress]
        sendData(message)
    }
    
    private func reportExecutionFinished(player: String) {
        if isHost {
            if !podium.contains(player) {
                podium.append(player)
                sendPodiumUpdate()
                checkGlobalCompletion()
            }
        } else {
            let finishedMessage: [String: Any] = ["type": "finished", "player": player]
            sendData(finishedMessage)
        }
    }
    
    // Invia lo startingProgress e il podio attuale a tutti
    func syncGameConfiguration() {
        guard isHost else { return }
        let configMessage: [String: Any] = [
            "type": "gameConfig",
            "startingProgress": startingProgress,
            "podium": podium
        ]
        sendData(configMessage)
    }
    
    private func sendPodiumUpdate() {
        let podiumMessage: [String: Any] = ["type": "podiumUpdate", "list": podium]
        sendData(podiumMessage)
    }
    
    private func checkGlobalCompletion() {
        let totalPlayers = session.connectedPeers.count + 1
        if podium.count >= totalPlayers && !isTaskCompleted {
            isTaskCompleted = true
            let endMessage: [String: Any] = ["type": "completed", "finalPodium": podium]
            sendData(endMessage)
        }
    }
    
    private func sendData(_ dictionary: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dictionary, options: []) else { return }
        guard !session.connectedPeers.isEmpty else { return }
        try? session.send(data, toPeers: session.connectedPeers, with: .reliable)
    }
}

extension TaskSessionManager: MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        
    }
    
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else { return }
        
        DispatchQueue.main.async {
            if let type = json["type"] as? String {
                switch type {
                case "gameConfig":
                    if let start = json["startingProgress"] as? CGFloat {
                        self.startingProgress = start
                        // Se non ho ancora iniziato a scuotere, mi allineo al punto di partenza
                        if let myProg = self.playersProgress[self.myPeerID.displayName], myProg == 0.0 || myProg == start {
                            self.playersProgress[self.myPeerID.displayName] = start
                        }
                    }
                case "progress":
                    if let player = json["player"] as? String, let value = json["value"] as? CGFloat {
                        self.playersProgress[player] = value
                    }
                case "finished":
                    if let player = json["player"] as? String {
                        self.reportExecutionFinished(player: player)
                    }
                case "podiumUpdate":
                    if let list = json["list"] as? [String] {
                        self.podium = list
                    }
                case "completed":
                    if let finalPodium = json["finalPodium"] as? [String] {
                        self.podium = finalPodium
                        self.isTaskCompleted = true
                    }
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
                self.playersProgress[peerID.displayName] = self.startingProgress
                // L'host invia la configurazione iniziale appena si connette un nuovo giocatore
                self.syncGameConfiguration()
            } else if state == .notConnected {
                self.playersProgress.removeValue(forKey: peerID.displayName)
                self.podium.removeAll(where: { $0 == peerID.displayName })
            }
        }
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
