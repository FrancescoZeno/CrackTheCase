import SwiftUI

struct ContentView: View {
    @StateObject private var sessionManager = LightSessionManager(displayName: "Player_\(Int.random(in: 100...999))")
    @State private var sliderValue: Double = 0.0
    
    let ocraColor = Color(red: 204/255, green: 153/255, blue: 51/255)
    
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            
            if sessionManager.isGameOver {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.red)
                    Text("GAME OVER")
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .foregroundColor(.red)
                    Text("The power grid has suffered a total short circuit!")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.7))
                }
                .transition(.scale)
            } else if sessionManager.isBlackoutFixed {
                VStack(spacing: 20) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.green)
                    Text("POWER RESTORED!")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundColor(.green)
                    Text("Across the entire campus")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.8))
                    Text("Continue your investigation...")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                .transition(.scale)
            } else {
                VStack(spacing: 10) {
                    HStack {
                        Spacer()
                        HStack(spacing: 8) {
                            Image(systemName: "timer")
                                .foregroundColor(.red)
                            Text("CRITICAL TIME: \(sessionManager.timeRemaining)s")
                                .font(.system(.title3, design: .monospaced)).bold()
                                .foregroundColor(.red)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 15)
                        .background(Color.red.opacity(0.15))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.red.opacity(0.4), lineWidth: 1)
                        )
                    }
                    .padding(.horizontal, 30)
                    .padding(.top, 15)
                    
                    HStack(spacing: 40) {
                        VStack(alignment: .leading, spacing: 15) {
                            Text("EMERGENCY BLACKOUT")
                                .font(.system(size: 28, weight: .black, design: .rounded))
                                .foregroundColor(ocraColor)
                                .tracking(1)
                            
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundColor(.red)
                                
                                Text("ACCELERATED TIME LOSS (-10s/s)! Stabilize immediately!")
                                    .font(.caption.bold())
                                    .foregroundColor(.red)
                            }
                            
                            Spacer()
                            
                            HStack(spacing: 30) {
                                VStack(alignment: .center, spacing: 5) {
                                    Text("REQUIRED")
                                        .font(.caption.bold())
                                        .foregroundColor(.gray)
                                    Text("\(Int(sessionManager.targetLight))%")
                                        .font(.system(size: 44, weight: .black, design: .monospaced))
                                        .foregroundColor(ocraColor)
                                }
                                .padding()
                                .background(Color.white.opacity(0.05))
                                .cornerRadius(10)
                                
                                VStack(alignment: .center, spacing: 5) {
                                    Text("TEAM AVERAGE")
                                        .font(.caption.bold())
                                        .foregroundColor(.gray)
                                    Text("\(Int(sessionManager.currentAverage))%")
                                        .font(.system(size: 44, weight: .black, design: .monospaced))
                                        .foregroundColor(abs(sessionManager.currentAverage - sessionManager.targetLight) < 2.0 ? .green : .red)
                                }
                                .padding()
                                .background(Color.white.opacity(0.05))
                                .cornerRadius(10)
                            }
                            
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        VStack(spacing: 20) {
                            Text("YOUR REGULATOR")
                                .font(.subheadline.bold())
                                .foregroundColor(ocraColor)
                            
                            Text("\(Int(sliderValue))%")
                                .font(.system(size: 36, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                            
                            Slider(value: $sliderValue, in: 0...100, step: 1.0)
                                .tint(ocraColor)
                                .padding(.horizontal, 10)
                                .onChange(of: sliderValue) { oldValue, newValue in
                                    sessionManager.updateMyLightValue(newValue)
                                }
                            
                            HStack {
                                Image(systemName: "lightbulb")
                                    .foregroundColor(.gray)
                                Spacer()
                                Image(systemName: "lightbulb.max.fill")
                                    .foregroundColor(ocraColor)
                            }
                            .padding(.horizontal, 15)
                        }
                        .padding(.vertical, 20)
                        .padding(.horizontal, 20)
                        .background(Color.white.opacity(0.03))
                        .cornerRadius(15)
                        .overlay(
                            RoundedRectangle(cornerRadius: 15)
                                .stroke(ocraColor.opacity(0.3), lineWidth: 1)
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 30)
                    .padding(.bottom, 20)
                }
            }
        }
        .supportedOrientations(.landscape)
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
