import SwiftUI
import CrackTheCaseCore

/// The final-accusation screen for the player who pressed "Vote": pick a
/// suspect, then confirm.
///
/// A standalone, parameter-driven view (rather than a `private` computed
/// property reading `ContentView`'s own `@State`/`ClientConnectivityService`)
/// specifically so it can be previewed — see the `#Preview`s below —
/// without a live host connection.
///
/// Deliberately a different shape from `NotebookView` (title centered
/// full-width up top, suspect grid centered below, full-width confirm
/// button at the bottom) rather than reusing its sidebar-plus-grid
/// arrangement: that layout earns its keep on the notebook screen, which
/// has a lot of dense status text stacked in the sidebar, but here there's
/// only a one-line title and subtitle — the sidebar read as mostly empty
/// space next to a cramped grid. This is also the single most consequential
/// tap in the whole game, so it gets a more deliberate, centered
/// composition instead of borrowing a layout built for a busier screen.
struct AccusationPickerView: View {
    let wronglyAccusedSuspectIDs: Set<String>
    @Binding var candidate: Suspect?
    let onConfirm: (Suspect) -> Void

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.red.opacity(0.4), Color.black], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    Text("WHO DO YOU ACCUSE?")
                        .font(.system(size: 28, weight: .black, design: .monospaced))
                        .foregroundStyle(.white)
                        .tracking(3)
                        .multilineTextAlignment(.center)

                    Text("Choose carefully: if you're wrong, the game continues but you'll have lost your chance.")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 60)
                .padding(.top, 20)

                Spacer(minLength: 8)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 18) {
                        ForEach(Suspects.all) { suspect in
                            let isSelected = candidate?.id == suspect.id
                            // Already confirmed wrong by a past accusation — no reason to
                            // waste another vote on them.
                            let isKnownInnocent = wronglyAccusedSuspectIDs.contains(suspect.id)

                            SuspectCardButton(
                                suspect: suspect,
                                isKnownInnocent: isKnownInnocent,
                                borderColor: isSelected ? .white : (isKnownInnocent ? .white.opacity(0.3) : suspect.color.color),
                                borderWidth: isSelected ? 4 : 2,
                                showXMark: false,
                                // Bigger than the notebook's cards (140×175)
                                // — this screen no longer shares its width
                                // with a status sidebar, and being the
                                // single most important decision in the
                                // game, it earns cards with more presence.
                                width: 160,
                                portraitHeight: 200,
                                onTap: {
                                    Haptics.impact(.medium)
                                    candidate = suspect
                                }
                            )
                            .shadow(color: isSelected ? .white.opacity(0.5) : .clear, radius: 10)
                        }
                    }
                    .padding(.horizontal, 24)
                }

                Spacer(minLength: 8)

                if let candidate {
                    Button {
                        onConfirm(candidate)
                        self.candidate = nil
                    } label: {
                        Text("CONFIRM: \(candidate.name.uppercased())")
                            .font(.system(size: 17, weight: .black, design: .monospaced))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.red)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .shadow(color: .red.opacity(0.5), radius: 10, y: 5)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 80)
                    .padding(.bottom, 20)
                }
            }
        }
    }
}

#Preview("Accusation picker — no candidate yet", traits: .landscapeRight) {
    AccusationPickerView(
        wronglyAccusedSuspectIDs: [],
        candidate: .constant(nil),
        onConfirm: { _ in }
    )
    .preferredColorScheme(.dark)
}

#Preview("Accusation picker — candidate selected", traits: .landscapeRight) {
    AccusationPickerView(
        wronglyAccusedSuspectIDs: [Suspects.all[0].id],
        candidate: .constant(Suspects.all[2]),
        onConfirm: { _ in }
    )
    .preferredColorScheme(.dark)
}
