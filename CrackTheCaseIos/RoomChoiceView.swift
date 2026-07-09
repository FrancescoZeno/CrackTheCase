import SwiftUI
import CrackTheCaseCore

/// The room-selection screen: a horizontally-scrolling strip of all 9 rooms
/// as cards, tap one to explore it on your turn.
///
/// A standalone, parameter-driven view (rather than a `private` computed
/// property reading `ContentView`'s own `@State`/`ClientConnectivityService`)
/// specifically so it can be previewed with a mock set of already-taken
/// rooms — see the `#Preview`s below — without a live host connection.
struct RoomChoiceView: View {
    let takenRooms: Set<RoomID>
    let onChoose: (RoomID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SELECT LOCATION")
                .font(.system(size: 24, weight: .black, design: .monospaced))
                .foregroundStyle(Color.phoenixGold)
                .tracking(4)
                .padding(.horizontal, 20)
                .padding(.top, 12)

            Text("Only 3 of the 9 rooms hide a clue")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.phoenixMuted)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(RoomID.allCases) { room in
                        let isTaken = takenRooms.contains(room)
                        Button {
                            Haptics.impact(.heavy)
                            onChoose(room)
                        } label: {
                            ZStack(alignment: .bottom) {
                                // Falls back to the SF Symbol icon (same
                                // treatment as `SuspectPortraitView`) if a
                                // cover photo is ever missing for this room.
                                if UIImage(named: room.coverAsset) != nil {
                                    Image(room.coverAsset)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 260, height: 170)
                                        .clipped()
                                        .grayscale(isTaken ? 1 : 0)
                                        .opacity(isTaken ? 0.4 : 1)
                                } else {
                                    Rectangle()
                                        .fill(isTaken ? Color.black.opacity(0.8) : Color.white.opacity(0.05))
                                        .frame(width: 260, height: 170)
                                        .overlay {
                                            Image(systemName: room.icon)
                                                .font(.system(size: 40, weight: .light))
                                                .foregroundStyle(isTaken ? Color.gray : Color.phoenixGold)
                                        }
                                }

                                LinearGradient(
                                    colors: [.black.opacity(0.85), .clear],
                                    startPoint: .bottom,
                                    endPoint: .center
                                )
                                .frame(width: 260, height: 90)

                                Text(room.displayName.uppercased())
                                    .font(.system(size: 15, weight: .black, design: .monospaced))
                                    .foregroundStyle(isTaken ? Color.gray : .white)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.55)
                                    .padding(.horizontal, 8)
                                    .padding(.bottom, 10)
                            }
                            .frame(width: 260, height: 170)
                            .overlay(Rectangle().strokeBorder(isTaken ? Color.gray.opacity(0.3) : Color.phoenixGold, lineWidth: 2))
                            .overlay {
                                if isTaken {
                                    Image(systemName: "slash.circle.fill")
                                        .font(.system(size: 44))
                                        .foregroundStyle(Color.red.opacity(0.7))
                                }
                            }
                            .clipShape(Rectangle())
                            // Explicit hit-testing shape over the full card
                            // — without it, a composite label (photo +
                            // gradient + text layered in a ZStack) can leave
                            // gaps in what SwiftUI treats as "the button",
                            // which reads as taps not registering until
                            // several tries.
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isTaken)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
}

#Preview("Room choice — start of round", traits: .landscapeRight) {
    ZStack {
        CinematicBackground().ignoresSafeArea()
        RoomChoiceView(takenRooms: [], onChoose: { _ in })
    }
    .preferredColorScheme(.dark)
}

#Preview("Room choice — a few taken", traits: .landscapeRight) {
    ZStack {
        CinematicBackground().ignoresSafeArea()
        RoomChoiceView(takenRooms: [.library, .assemblyHall, .cafeteria], onChoose: { _ in })
    }
    .preferredColorScheme(.dark)
}
