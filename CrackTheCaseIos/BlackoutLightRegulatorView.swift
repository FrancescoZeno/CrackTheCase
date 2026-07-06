import SwiftUI
import CrackTheCaseCore

/// The `lightRegulator` Black-out task: every player nudges their own
/// slider so the team's average lands on the target the host announced.
/// Unlike the other two Black-out tasks, this one succeeds or fails for
/// every player at once — there's no local "done" state here, since the
/// host marks everyone finished together once `client.blackoutLightAverage`
/// lands within tolerance of `client.blackoutLightTarget` (see
/// `GameSession.updateBlackoutLightValue(playerID:value:)`).
struct BlackoutLightRegulatorView: View {
    let client: ClientConnectivityService
    @State private var sliderValue: Double = 0
    /// Throttles network sends while dragging: the host re-broadcasts a
    /// full ~17-field session snapshot to every player on every update, so
    /// sending on every SwiftUI slider tick (which can fire dozens of times
    /// a second) would flood the connection right when several players are
    /// dragging at once. The value on release is always sent regardless,
    /// via the slider's `onEditingChanged`.
    @State private var lastSentAt: Date = .distantPast
    private let minSendInterval: TimeInterval = 0.1

    private var isOnTarget: Bool {
        abs(client.blackoutLightAverage - client.blackoutLightTarget) < GameSession.blackoutLightTolerance
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("EMERGENCY BLACKOUT")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(.phoenixGold)
                .tracking(1)

            Label("The lights won't come back until the team matches the target!", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.phoenixDestructive)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            HStack(spacing: 16) {
                VStack(spacing: 4) {
                    Text("TARGET")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.phoenixMuted)
                    Text("\(Int(client.blackoutLightTarget))%")
                        .font(.system(size: 34, weight: .black, design: .monospaced))
                        .foregroundStyle(.phoenixGold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.phoenixCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(spacing: 4) {
                    Text("TEAM AVERAGE")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.phoenixMuted)
                    Text("\(Int(client.blackoutLightAverage))%")
                        .font(.system(size: 34, weight: .black, design: .monospaced))
                        .foregroundStyle(isOnTarget ? .phoenixGreen : .phoenixDestructive)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.phoenixCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(.horizontal, 24)

            Spacer()

            VStack(spacing: 16) {
                Text("YOUR REGULATOR")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.phoenixGold)

                Text("\(Int(sliderValue))%")
                    .font(.system(size: 40, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)

                HStack {
                    Image(systemName: "lightbulb")
                        .foregroundStyle(.phoenixMuted)
                    Slider(value: $sliderValue, in: 0...100, step: 1) { isEditing in
                        // Always send the final value once the drag ends,
                        // regardless of the throttle window below.
                        guard !isEditing else { return }
                        lastSentAt = Date()
                        client.updateBlackoutLightValue(sliderValue)
                    }
                    .tint(.phoenixGold)
                    .onChange(of: sliderValue) { _, newValue in
                        let now = Date()
                        guard now.timeIntervalSince(lastSentAt) >= minSendInterval else { return }
                        lastSentAt = now
                        client.updateBlackoutLightValue(newValue)
                    }
                    Image(systemName: "lightbulb.max.fill")
                        .foregroundStyle(.phoenixGold)
                }
            }
            .padding(20)
            .background(Color.phoenixCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.phoenixGold.opacity(0.3), lineWidth: 1)
            )
            .padding(.horizontal, 24)

            Spacer()
        }
        .padding(.top, 20)
        .onAppear {
            client.updateBlackoutLightValue(sliderValue)
        }
    }
}
