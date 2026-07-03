import SwiftUI

struct MemoryCard: Identifiable {
    let id = UUID()
    let symbolName: String
    var isFaceUp: Bool = false
    var isMatched: Bool = false
}

enum TaskState {
    case countdown
    case playing
}

struct ContentView: View {
    // --- INTEGRATION CLOSURE FOR YOUR MAIN GAME ---
    var onCompletion: (Double) -> Void = { time in print("Task cleared in \(time)s") }
    
    // Internal Gameplay State
    @State private var taskState: TaskState = .countdown
    @State private var cards: [MemoryCard] = []
    @State private var selectedIndices: [Int] = []
    @State private var canInteract: Bool = true
    @State private var wrongSelection: Bool = false
    
    // Timers and Countdown
    @State private var countdownValue: Int = 5
    @State private var countdownTimer: Timer?
    @State private var startTime: Date?
    @State private var elapsedTime: Double = 0.0
    @State private var gameTimer: Timer?
    
    let ocraColor = Color(red: 204/255, green: 153/255, blue: 51/255)
    
    // CRIME & CAMPUS THEME SYMBOLS: Magnifying glass, Laptop, Becker (Flask), Drop
    let baseSymbols = [
        "magnifyingglass",
        "laptopcomputer",
        "flask.fill",
        "drop.fill"
    ]
    
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            
            switch taskState {
            case .countdown:
                // --- 5-SECOND COUNTDOWN WITH BRIEF DESCRIPTION ---
                VStack(spacing: 25) {
                    VStack(spacing: 8) {
                        Text("CRIME SCENE TASK")
                            .font(.system(size: 26, weight: .black, design: .rounded))
                            .foregroundColor(ocraColor)
                        
                        Text("Locate and match all 4 pairs of campus evidence.\nA single mismatch will hide all discovered clues, but the clock won't stop!")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.horizontal, 40)
                    }
                    
                    Text("\(countdownValue)")
                        .font(.system(size: 90, weight: .black, design: .monospaced))
                        .foregroundColor(ocraColor)
                        .id(countdownValue)
                }
                
            case .playing:
                // --- ACTIVE GAMEPLAY GRID ---
                VStack(spacing: 15) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("EVIDENCE CORRELATION")
                                .font(.system(size: 24, weight: .black, design: .rounded))
                                .foregroundColor(ocraColor)
                            Text("Find the matching evidence. Speed determines your turn order.")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.5))
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 8) {
                            Image(systemName: "stopwatch")
                                .foregroundColor(ocraColor)
                            Text(String(format: "%.2fs", elapsedTime))
                                .font(.system(.title3, design: .monospaced)).bold()
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 15)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.07))
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(ocraColor.opacity(0.3), lineWidth: 1))
                    }
                    .padding(.horizontal, 40)
                    
                    Spacer()
                    
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: 4), spacing: 20) {
                        ForEach(0..<cards.count, id: \.self) { index in
                            CardContainerView(
                                card: cards[index],
                                ocraColor: ocraColor,
                                isWrong: wrongSelection && selectedIndices.contains(index)
                            )
                            .aspectRatio(1.2, contentMode: .fit)
                            .onTapGesture {
                                handleCardSelection(at: index)
                            }
                        }
                    }
                    .padding(.horizontal, 60)
                    .frame(maxWidth: 700)
                    
                    Spacer()
                }
                .padding(.vertical, 20)
            }
        }
        .onAppear {
            startCountdownPhase()
        }
        .onDisappear {
            stopGameTimer()
            countdownTimer?.invalidate()
        }
    }
    
    // --- GAMEPLAY LOGIC ---
    private func startCountdownPhase() {
        let doubledSymbols = baseSymbols + baseSymbols
        let shuffled = doubledSymbols.shuffled()
        self.cards = shuffled.map { MemoryCard(symbolName: $0) }
        
        self.selectedIndices.removeAll()
        self.wrongSelection = false
        self.canInteract = true
        self.elapsedTime = 0.0
        
        self.countdownValue = 5
        self.taskState = .countdown
        
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if self.countdownValue > 1 {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                    self.countdownValue -= 1
                }
            } else {
                self.countdownTimer?.invalidate()
                self.countdownTimer = nil
                
                self.taskState = .playing
                self.startTime = Date()
                self.startGameTimer()
            }
        }
    }
    
    private func resumeClockAfterFailure() {
        self.selectedIndices.removeAll()
        self.wrongSelection = false
        self.canInteract = true
        // Il timer NON viene azzerato, ricalcola semplicemente l'offset corretto dal momento iniziale
        self.startGameTimer()
    }
    
    private func handleCardSelection(at index: Int) {
        guard canInteract, !cards[index].isFaceUp, !cards[index].isMatched else { return }
        
        withAnimation(.easeInOut(duration: 0.2)) {
            cards[index].isFaceUp = true
        }
        selectedIndices.append(index)
        
        if selectedIndices.count == 2 {
            canInteract = false
            let first = selectedIndices[0]
            let second = selectedIndices[1]
            
            if cards[first].symbolName == cards[second].symbolName {
                cards[first].isMatched = true
                cards[second].isMatched = true
                selectedIndices.removeAll()
                canInteract = true
                
                if cards.allSatisfy({ $0.isMatched }) {
                    stopGameTimer()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        onCompletion(self.elapsedTime)
                    }
                }
            } else {
                // ERRORE: Il tempo continua a scorrere in background mentre mostriamo l'errore visivo
                withAnimation(.default) {
                    wrongSelection = true
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    // HARDCORE PUNISHMENT: Tutte le carte tornano coperte
                    withAnimation(.easeInOut(duration: 0.25)) {
                        for i in 0..<cards.count {
                            cards[i].isFaceUp = false
                            cards[i].isMatched = false
                        }
                    }
                    resumeClockAfterFailure()
                }
            }
        }
    }
    
    private func startGameTimer() {
        gameTimer?.invalidate()
        gameTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            if let start = startTime {
                self.elapsedTime = Date().timeIntervalSince(start)
            }
        }
    }
    
    private func stopGameTimer() {
        gameTimer?.invalidate()
        gameTimer = nil
    }
}

// --- CARD UI CONTAINER ---
struct CardContainerView: View {
    let card: MemoryCard
    let ocraColor: Color
    let isWrong: Bool
    
    var body: some View {
        ZStack {
            if card.isFaceUp || card.isMatched {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isWrong ? Color.red : (card.isMatched ? Color.green.opacity(0.8) : ocraColor), lineWidth: 2)
                    )
                
                Image(systemName: card.symbolName)
                    .font(.system(size: 38, weight: .bold))
                    .foregroundColor(isWrong ? .red : (card.isMatched ? .green : .white))
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(ocraColor.opacity(0.3), lineWidth: 1.5)
                    )
                    .overlay(
                        Image(systemName: "scope")
                            .font(.title2)
                            .foregroundColor(ocraColor.opacity(0.25))
                    )
            }
        }
        .rotation3DEffect(
            .degrees(card.isFaceUp ? 180 : 0),
            axis: (x: 0.0, y: 1.0, z: 0.0)
        )
    }
}
