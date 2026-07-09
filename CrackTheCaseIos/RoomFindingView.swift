import SwiftUI
import CrackTheCaseCore

/// Full-screen reveal of what a player found in the room they just chose.
///
/// The room's own "clue scene" photo (`clueAsset`) fills the whole screen,
/// edge to edge — these photos are shot specifically to be displayed that
/// way, with a centered prop (a book, a loose sheet of paper…) meant to
/// hold the clue text, so constraining it down to a small box wastes the
/// shot. The "indizio" (clue) itself — icon + title/text — sits in its own
/// compact, self-contained card on top of the photo instead of being laid
/// out free-form over it, so it reads clearly regardless of what the photo
/// underneath looks like.
///
/// A standalone, parameter-driven view (rather than a `private` computed
/// property reading `ContentView`'s own `@State`/`ClientConnectivityService`)
/// specifically so it can be previewed in isolation — see the `#Preview`s
/// below — without a live host connection.
struct RoomFindingView: View {
    /// Which room this finding is for — only used to look up `clueAsset`.
    /// `nil` falls back to a plain gradient (shouldn't happen in practice:
    /// the call site always sets this right before `chooseRoom`).
    let room: RoomID?
    let finding: RoomFinding
    let secondsRemaining: Int

    var body: some View {
        ZStack {
            if let room, let uiImage = UIImage(named: room.clueAsset) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .ignoresSafeArea()
            } else {
                LinearGradient(colors: [.black, .phoenixCard], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            }

            // Scrim over the whole photo (not just behind the card) so the
            // card reads clearly regardless of how bright/busy the photo
            // underneath is.
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            clueCard

            // Reading-time cooldown, a small corner badge. The fill is a
            // fixed dark tone rather than `iconColor.opacity(0.35)` — for
            // `.empty` findings `iconColor` is `.phoenixMuted` (a muted
            // gray), which at 35% opacity read as nearly invisible over a
            // bright/busy room photo. `iconColor` still does its job as
            // the ring color (keeps the existing gold/gray/red coding), but
            // the badge itself is always legible regardless of finding.
            VStack {
                HStack {
                    Spacer()
                    Text("\(secondsRemaining)")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.55), in: Circle())
                        .overlay(Circle().strokeBorder(iconColor, lineWidth: 3))
                        .shadow(color: .black.opacity(0.5), radius: 8)
                }
                Spacer()
            }
            .padding(20)
        }
    }

    /// The compact "indizio" card — icon + title/text — roughly a 220pt-wide
    /// box (height left free so longer clue text isn't clipped) instead of
    /// free-floating text laid over the full-screen photo.
    private var clueCard: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .padding(12)
                .background(iconColor, in: Circle())
                .shadow(color: iconColor.opacity(0.6), radius: 10)

            switch finding {
            case .clue(let clue):
                Text(clue.title)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(clue.text)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            case .empty:
                Text("This area is clear")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text("Nothing to see here. Time to move on.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
            case .hiddenByPenalty:
                Text("Visibility compromised")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text("You were too slow in the emergency task. Any clues here are hidden in darkness.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(width: 220)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(iconColor.opacity(0.6), lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.5), radius: 14, y: 8)
    }

    private var icon: String {
        switch finding {
        case .clue: return "doc.text.magnifyingglass"
        case .empty: return "door.left.hand.closed"
        case .hiddenByPenalty: return "eye.slash.fill"
        }
    }

    private var iconColor: Color {
        switch finding {
        case .clue: return .phoenixGold
        case .empty: return .phoenixMuted
        case .hiddenByPenalty: return .phoenixDestructive
        }
    }
}

#Preview("Room finding — clue", traits: .landscapeRight) {
    RoomFindingView(
        room: .library,
        finding: .clue(Clue(
            title: "Torn Ledger Page",
            text: "A page has been ripped out right where last Tuesday's entry should be."
        )),
        secondsRemaining: 7
    )
    .preferredColorScheme(.dark)
}

#Preview("Room finding — empty room", traits: .landscapeRight) {
    RoomFindingView(room: .gym, finding: .empty, secondsRemaining: 4)
        .preferredColorScheme(.dark)
}

#Preview("Room finding — hidden by penalty", traits: .landscapeRight) {
    RoomFindingView(room: .cafeteria, finding: .hiddenByPenalty, secondsRemaining: 9)
        .preferredColorScheme(.dark)
}

#Preview("Room finding — no photo (fallback)", traits: .landscapeRight) {
    RoomFindingView(room: nil, finding: .empty, secondsRemaining: 5)
        .preferredColorScheme(.dark)
}
