import SwiftUI
import Combine
import CoreMotion

class HyperActiveShakeManager: ObservableObject {
    private let motionManager = CMMotionManager()
    private var lastUpdate: TimeInterval = 0
    
    // SOGLIA CALIBRATA: Alzata a 2.3 per ignorare respiri e piccoli spostamenti.
    // Richiede uno scatto deciso per attivarsi.
    private let shakeThreshold: Double = 2.3
    
    // Memoria del segno dell'ultima accelerazione per intercettare l'inversione di marcia (scossa completa)
    private var lastXSign: Double = 0
    private var lastYSign: Double = 0
    private var lastZSign: Double = 0
    
    var onShakeDetected: (() -> Void)?
    
    init() {
        startMonitoring()
    }
    
    func startMonitoring() {
        guard motionManager.isAccelerometerAvailable else { return }
        motionManager.accelerometerUpdateInterval = 1.0 / 60.0
        
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, error in
            guard let self = self, let acceleration = data?.acceleration else { return }
            
            let currentTime = CACurrentMediaTime()
            // Freno di ripetizione calibrato a 0.15 secondi per dare il tempo di fare il movimento di ritorno
            guard currentTime - self.lastUpdate > 0.15 else { return }
            
            var shakeTriggered = false
            
            // 1. Controllo asse X (Scossa sinistra / destra)
            if abs(acceleration.x) > self.shakeThreshold {
                let currentSign = acceleration.x > 0 ? 1.0 : -1.0
                if self.lastXSign != 0 && self.lastXSign != currentSign {
                    shakeTriggered = true
                }
                self.lastXSign = currentSign
            }
            
            // 2. Controllo asse Y (Scossa avanti / indietro - orientamento landscape)
            if abs(acceleration.y) > self.shakeThreshold {
                let currentSign = acceleration.y > 0 ? 1.0 : -1.0
                if self.lastYSign != 0 && self.lastYSign != currentSign {
                    shakeTriggered = true
                }
                self.lastYSign = currentSign
            }
            
            // 3. Controllo asse Z (Scossa sussultoria alto / basso)
            if abs(acceleration.z) > self.shakeThreshold {
                let currentSign = acceleration.z > 0 ? 1.0 : -1.0
                if self.lastZSign != 0 && self.lastZSign != currentSign {
                    shakeTriggered = true
                }
                self.lastZSign = currentSign
            }
            
            // Se c'è stata un'accelerazione forte SEGUITA da un'inversione di marcia netta
            if shakeTriggered {
                self.lastUpdate = currentTime
                // Resetta i segni per costringere a fare un nuovo shake da capo
                self.lastXSign = 0
                self.lastYSign = 0
                self.lastZSign = 0
                
                self.onShakeDetected?()
            }
        }
    }
    
    deinit {
        motionManager.stopAccelerometerUpdates()
    }
}

struct HyperShakeModifier: ViewModifier {
    @StateObject private var shakeManager = HyperActiveShakeManager()
    let action: () -> Void
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                shakeManager.onShakeDetected = action
            }
    }
}

extension View {
    func onHyperShake(perform action: @escaping () -> Void) -> some View {
        self.modifier(HyperShakeModifier(action: action))
    }
}
