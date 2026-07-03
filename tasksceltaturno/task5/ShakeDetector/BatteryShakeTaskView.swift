import SwiftUI

struct BatteryView: View {
    var progress: CGFloat
    let totalBars = 10 // Portata a 10 tacchette
    
    let ocraColor = Color(red: 204/255, green: 153/255, blue: 51/255)
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                HStack(spacing: 3) {
                    ForEach(0..<totalBars, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(shouldFillBar(index: index) ? barColor(for: index) : Color.gray.opacity(0.15))
                            .animation(.spring(), value: progress)
                    }
                }
                .padding(6)
                .frame(width: 220, height: 75) // Allargata per fare spazio alle 10 tacchette
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(ocraColor, lineWidth: 4)
                )
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(ocraColor)
                    .frame(width: 10, height: 25)
            }
            
            Text("\(Int(progress * 100))%")
                .font(.system(.body, design: .monospaced)).bold()
                .foregroundColor(ocraColor)
        }
    }
    
    private func shouldFillBar(index: Int) -> Bool {
        let barThreshold = CGFloat(index) / CGFloat(totalBars)
        return progress > barThreshold
    }
    
    // Assegna il colore specifico ad ogni tacchetta in base alla sua posizione (da 0 a 9)
    private func barColor(for index: Int) -> Color {
        switch index {
        case 0, 1:
            return .red       // 10% e 20%
        case 2, 3, 4:
            return .orange    // 30%, 40%, 50%
        case 5, 6, 7:
            return .yellow    // 60%, 70%, 80%
        default:
            return .green     // 90% e 100%
        }
    }
}
