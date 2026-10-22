import SwiftUI

/// Compact closed-notch wing: "CHI 98 – BOS 94 Q4" for a live tracked game,
/// cycling every 8 s when several are live. Renders nothing when no tracked
/// team is playing, so the integrator can compose it unconditionally.
struct ScoreWing: View {
    @ObservedObject private var store = ScoresStore.shared

    private static let cycleSeconds: TimeInterval = 8

    var body: some View {
        let live = store.liveGames
        if live.count == 1 {
            label(for: live[0])
        } else if live.count > 1 {
            // Anchored to midnight (not `.now`) so store updates don't reset the cycle.
            let anchor = Calendar.current.startOfDay(for: Date())
            TimelineView(.periodic(from: anchor, by: Self.cycleSeconds)) { context in
                let index = Int(context.date.timeIntervalSince(anchor) / Self.cycleSeconds) % live.count
                label(for: live[max(0, index)])
            }
        }
    }

    private func label(for game: GameSummary) -> some View {
        HStack(spacing: 4) {
            Text("\(game.away.abbreviation) \(game.away.score ?? 0)")
            Text("–")
                .foregroundStyle(WingStyle.muted)
            Text("\(game.home.abbreviation) \(game.home.score ?? 0)")
            Text(game.periodLabel)
                .foregroundStyle(WingStyle.secondary)
        }
        .font(WingStyle.label)
        .foregroundStyle(WingStyle.primary)
        .lineLimit(1)
        .contentTransition(.numericText())
        .padding(.horizontal, WingStyle.inset)
        .frame(maxHeight: .infinity)
        .transition(WingStyle.transition)
        .animation(WingStyle.animation, value: game)
    }
}
