import SwiftUI

struct ContentView: View {
    @StateObject private var sessionManager = TaskSessionManager(displayName: "Player_\(Int.random(in: 100...999))")
    @State private var myProgress: CGFloat = 0.0
    @State private var hasInitializedProgress = false
    
    let ocraColor = Color(red: 204/255, green: 153/255, blue: 51/255)
    
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            
            if sessionManager.isTaskCompleted {
                VStack(spacing: 20) {
                    Text("ORDINE DEI TURNI")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundColor(.green)
                        .tracking(2)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(0..<sessionManager.podium.count, id: \.self) { index in
                            HStack(spacing: 20) {
                                Text("\(index + 1)°")
                                    .font(.title2.bold())
                                    .foregroundColor(index == 0 ? .yellow : ocraColor)
                                    .frame(width: 40, alignment: .leading)
                                
                                Text(sessionManager.podium[index])
                                    .font(.title3)
                                    .foregroundColor(.white)
                                
                                Spacer()
                                
                                Text(index == 0 ? "Inizia per primo!" : "Turno \(index + 1)")
                                    .font(.caption.bold())
                                    .foregroundColor(.gray)
                            }
                            .padding(.horizontal)
                            .frame(width: 400, height: 45)
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(8)
                        }
                    }
                    .padding()
                }
                .transition(.move(edge: .bottom))
            } else {
                VStack(spacing: 20) {
                    if myProgress >= 1.0 {
                        VStack(spacing: 10) {
                            Text("FINITO!")
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .foregroundColor(.yellow)
                            Text("Attendi che gli altri finiscano...")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    } else {
                        VStack(spacing: 15) {
                            Text("SHAKE IT!")
                                .font(.system(size: 42, weight: .black, design: .rounded))
                                .foregroundColor(ocraColor)
                                .tracking(3)
                            
                            Text("Muovi il telefono per caricare la batteria!")
                                .font(.headline)
                                .foregroundColor(ocraColor.opacity(0.6))
                        }
                    }
                    
                    BatteryView(progress: myProgress)
                        .scaleEffect(1.2)
                        .padding(.top, 10)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .supportedOrientations(.landscape)
        .onAppear {
            myProgress = sessionManager.startingProgress
        }
        .onReceive(sessionManager.$startingProgress) { newStart in
            if !hasInitializedProgress || myProgress < newStart {
                myProgress = newStart
                hasInitializedProgress = true
            }
        }
        .onHyperShake {
            guard myProgress < 1.0 && !sessionManager.isTaskCompleted else { return }
            
            // Incremento impostato esattamente al 10% (0.10) per ogni shake valido
            myProgress = min(myProgress + 0.10, 1.0)
            sessionManager.updateMyProgress(myProgress)
        }
    }
}

extension View {
    func supportedOrientations(_ orientations: UIInterfaceOrientationMask) -> some View {
        self.onAppear {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations))
            }
        }
    }
}
