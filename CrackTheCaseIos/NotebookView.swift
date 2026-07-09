import SwiftUI
import CrackTheCaseCore

/// The notebook screen: this player's status/vote column on the left, the
/// full 6-suspect grid (tap to mark ruled-out) on the right.
///
/// A standalone, parameter-driven view (rather than a `private` computed
/// property reading `ContentView`'s own `@State`/`ClientConnectivityService`)
/// specifically so it can be previewed with mock game state — see the
/// `#Preview`s below — without a live host connection.
struct NotebookView: View {
    let roundNumber: Int
    let isCurrentRoundBlackout: Bool
    let localPlayerID: UUID
    let players: [Player]
    let roomVisitLog: [RoomVisit]
    let collectedClues: [(room: RoomID, clue: Clue)]
    let failedAccusationPlayerIDs: Set<UUID>
    let votingBanRoundNumbers: [UUID: Int]
    let lastAccusation: Accusation?
    /// Suspects this player has personally accused and gotten wrong,
    /// accumulated across the whole game — owned by the caller (it persists
    /// across notebook visits, unlike `excludedSuspectIDs` below).
    let wronglyAccusedSuspectIDs: Set<String>
    let onStartVoting: () -> Void

    /// Manual "ruled out" toggles. Owned by `ContentView` (a `@Binding`
    /// here, not local `@State`): this view is torn down and rebuilt from
    /// scratch every time the phase leaves `.notebook` and comes back
    /// (`.minigame` → `.roomSelection` → `.notebook` repeats every round —
    /// `content`'s phase `switch` in `ContentView` simply stops rendering
    /// this case in between), so `@State` here would silently reset to
    /// empty each round. A previous version made exactly that mistake,
    /// reasoning the toggles were "purely local" — true in the sense that
    /// they're never sent to the host, but they still need to *persist*
    /// across this view's repeated construction, which only a binding into
    /// a longer-lived owner (`ContentView`, reset only at `.lobby`) can do.
    @Binding var excludedSuspectIDs: Set<String>

    var body: some View {
        // A `GeometryReader` around the whole thing, not just an inner
        // `ScrollView` left to negotiate its own height implicitly with
        // its container: `GeometryReader` is *guaranteed* by SwiftUI to
        // always report back the exact size it was given (unlike a plain
        // `ScrollView`/`VStack`, which can end up hugging its own content
        // instead of the space actually available, depending on what's
        // upstream) — so `geo.size.height` below is unambiguously the real
        // available height, both in the running app and in an Xcode
        // `#Preview`. That's what makes the height math on the left column
        // reliable: `ScrollView` gets exactly "whatever's left after
        // `voteButton`," not "however much it feels like."
        GeometryReader { geo in
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    // Everything here is variable-height (clue count grows
                    // across the game, room recap/banners come and go) —
                    // wrapped in its own `ScrollView` instead of relying on
                    // a bare `Spacer` to push `voteButton` down. When the
                    // combined banners (wrong-accusation + room recap +
                    // clues + failed-accusation label) exceed the space
                    // available, the `ScrollView` scrolls internally
                    // instead of overflowing past the screen edges, so
                    // `voteButton` below it is always at a fixed, reachable
                    // position.
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("SUSPECT DATABASE")
                                .font(.system(size: 18, weight: .black, design: .monospaced))
                                .foregroundStyle(.white)
                                .tracking(3)
                                .fixedSize(horizontal: false, vertical: true)

                            Text("ROUND \(roundNumber)")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(.phoenixMuted)
                                .tracking(2)

                            Label("Tap a suspect to mark them with an X once the clues rule them out.", systemImage: "xmark.circle")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.6))
                                .fixedSize(horizontal: false, vertical: true)

                            if let lastAccusation, !lastAccusation.wasCorrect, lastAccusation.playerID == localPlayerID {
                                wrongAccusationBanner(lastAccusation)
                            }

                            if roomVisitLog.contains(where: { $0.playerID == localPlayerID }) {
                                roomVisitRecap
                            }

                            if !collectedClues.isEmpty {
                                cluesSection
                            }

                            if !failedAccusationPlayerIDs.isEmpty {
                                Label(
                                    "\(failedAccusationPlayerIDs.count) failed accusation\(failedAccusationPlayerIDs.count == 1 ? "" : "s") this round",
                                    systemImage: "xmark.seal.fill"
                                )
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(.phoenixMuted)
                            }
                        }
                    }

                    // Fixed footer, outside the scroll — always reachable
                    // at the same spot regardless of how much content is
                    // above.
                    if isCurrentRoundBlackout {
                        Text("VOTING OFFLINE - BLACKOUT")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.phoenixGold)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        voteButton
                    }
                }
                // Explicit height, not implicit — `geo.size.height` is the
                // real available height (see the `GeometryReader` comment
                // above); 40 = the 20+20 vertical padding added right
                // below, so the padded result exactly fills `geo.size.height`
                // rather than overflowing it.
                .frame(width: 200, height: geo.size.height - 40)
                .padding(.leading, 24)
                .padding(.vertical, 20)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(Suspects.all) { suspect in
                            // Known wrong from a failed accusation of this
                            // suspect — permanently disabled, not just a
                            // manual toggle the player can undo.
                            let isKnownInnocent = wronglyAccusedSuspectIDs.contains(suspect.id)
                            let isManuallyExcluded = excludedSuspectIDs.contains(suspect.id)

                            SuspectCardButton(
                                suspect: suspect,
                                isKnownInnocent: isKnownInnocent,
                                borderColor: isKnownInnocent ? .white.opacity(0.3) : (isManuallyExcluded ? .red : suspect.color.color),
                                borderWidth: 2,
                                showXMark: isManuallyExcluded,
                                width: 140,
                                portraitHeight: 175,
                                onTap: {
                                    guard !isKnownInnocent else { return }
                                    Haptics.impact(.light)
                                    if isManuallyExcluded {
                                        excludedSuspectIDs.remove(suspect.id)
                                    } else {
                                        excludedSuspectIDs.insert(suspect.id)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.vertical, 20)
                    .padding(.trailing, 24)
                }
            }
        }
    }

    /// Compact reminder of which room *this player* explored this round —
    /// deliberately shows only the local player's own pick, not the rest of
    /// `roomVisitLog` (the shared, public log of every player's pick):
    /// showing other players' rooms here read as spoiler-adjacent noise
    /// (and could be misread as "the app got someone's room wrong" if a
    /// player forgot who went where), when this screen is about this
    /// player's own progress.
    private var roomVisitRecap: some View {
        Group {
            if let myVisit = roomVisitLog.first(where: { $0.playerID == localPlayerID }) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("YOUR ROOM")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.phoenixMuted)
                        .tracking(1)

                    Text(myVisit.roomID.displayName)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
    }

    /// Every distinct clue this player has personally found so far this
    /// game. Persists across rounds (unlike `RoomFindingView`'s 10-second
    /// reveal), so a player can always check back on what they've actually
    /// learned instead of having to remember it from a screen that already
    /// disappeared.
    private var cluesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("YOUR CLUES (\(collectedClues.count)/2)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.phoenixMuted)
                .tracking(1)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(collectedClues.enumerated()), id: \.offset) { _, entry in
                    HStack(spacing: 8) {
                        if let uiImage = UIImage(named: entry.room.clueAsset) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 28, height: 28)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        Text(entry.clue.title)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    /// The "cast an accusation" button — one of four mutually exclusive
    /// states: already failed this round, serving next-round's penalty for
    /// a *previous* round's wrong guess (see `GameSession.votingBanRoundNumbers`),
    /// still short of the 2 clues needed to accuse at all, or free to vote.
    private var voteButton: some View {
        let hasFailed = failedAccusationPlayerIDs.contains(localPlayerID)
        let isBanned = votingBanRoundNumbers[localPlayerID] == roundNumber
        let hasEnoughClues = collectedClues.count >= 2
        let isDisabled = hasFailed || isBanned || !hasEnoughClues

        return Button {
            Haptics.notify(.warning)
            onStartVoting()
        } label: {
            Text(voteButtonText(hasFailed: hasFailed, isBanned: isBanned, hasEnoughClues: hasEnoughClues))
                .font(.system(size: 15, weight: .black, design: .monospaced))
                .multilineTextAlignment(.center)
                .foregroundStyle(isDisabled ? .white.opacity(0.5) : .black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(voteButtonBackground(hasFailed: hasFailed, isBanned: isBanned, hasEnoughClues: hasEnoughClues))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private func voteButtonText(hasFailed: Bool, isBanned: Bool, hasEnoughClues: Bool) -> String {
        if hasFailed { return "ACCUSATION FAILED" }
        if isBanned { return "SKIPPING THIS ROUND\n(wrong guess last round)" }
        if !hasEnoughClues { return "COLLECT ALL 2 CLUES (\(collectedClues.count)/2)" }
        return "INITIATE ACCUSATION"
    }

    /// A wrong guess (this round or last) stays visually distinct — a muted
    /// red — from simply not having found every clue yet, which isn't a
    /// failure state and gets a neutral, non-alarming tint instead.
    private func voteButtonBackground(hasFailed: Bool, isBanned: Bool, hasEnoughClues: Bool) -> Color {
        if hasFailed || isBanned { return Color.red.opacity(0.3) }
        if !hasEnoughClues { return Color.white.opacity(0.08) }
        return Color.phoenixDestructive
    }

    private func wrongAccusationBanner(_ accusation: Accusation) -> some View {
        let accuserName = players.first { $0.id == accusation.playerID }?.nickname ?? "A player"
        let suspectName = Suspects.all.first { $0.id == accusation.suspectID }?.name ?? "someone"
        return Label("\(accuserName) accused \(suspectName) — wrong! The game continues.", systemImage: "xmark.circle.fill")
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(.phoenixDestructive)
            .padding(12)
            .phoenixCardStyle(cornerRadius: 14)
    }
}

#Preview("Notebook — fresh round", traits: .landscapeRight) {
    let playerID = UUID()
    ZStack {
        CinematicBackground().ignoresSafeArea()
        NotebookView(
            roundNumber: 2,
            isCurrentRoundBlackout: false,
            localPlayerID: playerID,
            players: [Player(id: playerID, nickname: "Ada", avatar: .blue, isReady: true)],
            roomVisitLog: [RoomVisit(playerID: playerID, roomID: .library)],
            collectedClues: [(room: .library, clue: Clue(title: "Torn Page", text: "A page is missing."))],
            failedAccusationPlayerIDs: [],
            votingBanRoundNumbers: [:],
            lastAccusation: nil,
            wronglyAccusedSuspectIDs: [],
            onStartVoting: {},
            excludedSuspectIDs: .constant([])
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Notebook — 2 clues, ready to vote", traits: .landscapeRight) {
    let playerID = UUID()
    ZStack {
        CinematicBackground().ignoresSafeArea()
        NotebookView(
            roundNumber: 4,
            isCurrentRoundBlackout: false,
            localPlayerID: playerID,
            players: [Player(id: playerID, nickname: "Ada", avatar: .blue, isReady: true)],
            roomVisitLog: [RoomVisit(playerID: playerID, roomID: .gym)],
            collectedClues: [
                (room: .library, clue: Clue(title: "Torn Page", text: "A page is missing.")),
                (room: .gym, clue: Clue(title: "Muddy Footprint", text: "A single muddy footprint by the lockers.")),
            ],
            failedAccusationPlayerIDs: [],
            votingBanRoundNumbers: [:],
            lastAccusation: nil,
            wronglyAccusedSuspectIDs: [],
            onStartVoting: {},
            excludedSuspectIDs: .constant([])
        )
    }
    .preferredColorScheme(.dark)
}

// Worst case for the overflow fix in `body` above: wrong-accusation banner +
// room recap + clues section + failed-accusation label all shown at once —
// exactly the scenario that used to push `voteButton` off the bottom of
// the screen before the internal `ScrollView` was added.
#Preview("Notebook — every banner at once (worst case)", traits: .landscapeRight) {
    let playerID = UUID()
    ZStack {
        CinematicBackground().ignoresSafeArea()
        NotebookView(
            roundNumber: 5,
            isCurrentRoundBlackout: true,
            localPlayerID: playerID,
            players: [Player(id: playerID, nickname: "Ada", avatar: .blue, isReady: true)],
            roomVisitLog: [RoomVisit(playerID: playerID, roomID: .cafeteria)],
            collectedClues: [
                (room: .library, clue: Clue(title: "Torn Page", text: "A page is missing.")),
                (room: .gym, clue: Clue(title: "Muddy Footprint", text: "A single muddy footprint by the lockers.")),
            ],
            failedAccusationPlayerIDs: [playerID],
            votingBanRoundNumbers: [playerID: 5],
            lastAccusation: Accusation(playerID: playerID, suspectID: Suspects.all[0].id, wasCorrect: false),
            wronglyAccusedSuspectIDs: [Suspects.all[0].id],
            onStartVoting: {},
            excludedSuspectIDs: .constant([])
        )
    }
    .preferredColorScheme(.dark)
}
