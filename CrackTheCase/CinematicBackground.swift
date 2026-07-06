import SwiftUI

struct CinematicBackground: View {
    @State private var phase1: CGFloat = 0
    @State private var phase2: CGFloat = .pi

    var body: some View {
        ZStack {
            Color(red: 8/255, green: 8/255, blue: 12/255).ignoresSafeArea()
            
            GeometryReader { geo in
                ZStack {
                    // Main animated ambient glow
                    Circle()
                        .fill(Color.phoenixGold.opacity(0.15))
                        .frame(width: geo.size.width * 1.5, height: geo.size.width * 1.5)
                        .blur(radius: 200)
                        .offset(x: cos(phase1) * 300, y: sin(phase1) * 300)

                    Circle()
                        .fill(Color.phoenixGreenDark.opacity(0.15))
                        .frame(width: geo.size.width * 1.8, height: geo.size.width * 1.8)
                        .blur(radius: 250)
                        .offset(x: -sin(phase2) * 400, y: cos(phase2) * 400)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .drawingGroup()
            }
            .ignoresSafeArea()
        }
        .onAppear {
            withAnimation(.linear(duration: 25).repeatForever(autoreverses: false)) {
                phase1 = .pi * 2
            }
            withAnimation(.linear(duration: 35).repeatForever(autoreverses: false)) {
                phase2 = .pi * 2 + .pi
            }
        }
    }
}
