import SwiftUI

/// The Scores widget for the open notch (Tools tab): one row per tracked
/// team's game — live first, then upcoming with start time, then finals.
/// Designed for the dark notch background — white text, subtle opacity layers.
struct ScoresWidgetView: View {
    @ObservedObject private var store = ScoresStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if store.games.isEmpty {
                        emptyState
                    } else {
                        section("Live", store.liveGames)
                        section("Upcoming", store.upcomingGames)
                        section("Final", store.finalGames)
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: store.games)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            store.start()
            store.refreshIfStale()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            Label("Scores", systemImage: "sportscourt")
                .font(HubStyle.title)
                .foregroundStyle(.white.opacity(0.92))
            Spacer()
            if let error = store.lastError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.orange.opacity(0.8))
                    .lineLimit(1)
            } else if let updated = store.lastUpdated {
                Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
                    .monospacedDigit()
            }
            Button {
                store.refreshNow()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(store.isRefreshing ? 0.2 : 0.45))
            }
            .buttonStyle(.plain)
            .disabled(store.isRefreshing)
            .help("Refresh now")
        }
    }

    // MARK: Sections

    @ViewBuilder
    private func section(_ title: String, _ games: [GameSummary]) -> some View {
        if !games.isEmpty {
            Text(title.uppercased())
                .font(HubStyle.section)
                .tracking(HubStyle.sectionTracking)
                .foregroundStyle(.white.opacity(0.35))
                .padding(.horizontal, 8)
                .padding(.top, 4)
            ForEach(games) { game in
                GameRowView(game: game)
            }
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "sportscourt")
                .font(HubStyle.emptyGlyph)
                .foregroundStyle(.white.opacity(0.25))
            Text(emptyTitle)
                .font(HubStyle.emptyTitle)
                .foregroundStyle(.white.opacity(0.5))
            Text(emptySubtitle)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }

    private var emptyTitle: String {
        if store.config.teams.isEmpty { return "No teams selected" }
        if store.lastUpdated == nil { return store.lastError == nil ? "Loading scores…" : "Scores unavailable" }
        return "No games this week"
    }

    private var emptySubtitle: String {
        if store.config.teams.isEmpty { return "Pick teams in Settings → Scores" }
        if store.lastUpdated == nil && store.lastError != nil { return "Check your connection" }
        return "Your teams' next games will show up here"
    }
}

// MARK: - Game row

private struct GameRowView: View {
    let game: GameSummary
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: game.league.systemImage)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.35))
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 3) {
                teamLine(game.away, opponent: game.home)
                teamLine(game.home, opponent: game.away)
            }

            Spacer(minLength: 8)

            statusView
                .frame(width: 92, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: HubStyle.rowRadius)
                .fill(Color.white.opacity(hovering ? 0.06 : 0))
        )
        .contentShape(Rectangle())
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.12)) { hovering = inside }
        }
        .contextMenu {
            if let url = game.espnURL {
                Button("Open on ESPN") { NSWorkspace.shared.open(url) }
            }
        }
    }

    private func teamLine(_ side: GameSummary.Side, opponent: GameSummary.Side) -> some View {
        HStack(spacing: 6) {
            Text(side.abbreviation)
                .font(.system(size: 12.5, weight: side.isTracked ? .semibold : .regular))
                .foregroundStyle(.white.opacity(side.isTracked ? 0.92 : 0.7))
                .frame(width: 38, alignment: .leading)
            Text(side.name)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if let score = side.score {
                Text("\(score)")
                    .font(HubStyle.bodyEmphasis)
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(isAhead(side, of: opponent) ? 0.95 : 0.5))
                    .contentTransition(.numericText())
            }
        }
    }

    /// Winner of a final, or the leader (or tied) in a live game.
    private func isAhead(_ side: GameSummary.Side, of opponent: GameSummary.Side) -> Bool {
        if game.status == .final, side.isWinner || opponent.isWinner { return side.isWinner }
        return (side.score ?? 0) >= (opponent.score ?? 0)
    }

    @ViewBuilder
    private var statusView: some View {
        switch game.status {
        case .live:
            HStack(spacing: 5) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 5, height: 5)
                Text(game.detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .monospacedDigit()
                    .lineLimit(1)
            }
        case .pre:
            VStack(alignment: .trailing, spacing: 2) {
                Text(startDay)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
                Text(startClock)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .monospacedDigit()
            }
        case .final:
            Text(game.detail)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
        }
    }

    private var startDay: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(game.startTime) { return "Today" }
        if calendar.isDateInTomorrow(game.startTime) { return "Tomorrow" }
        return game.startTime.formatted(.dateTime.weekday(.wide))
    }

    private var startClock: String {
        // ESPN reports unscheduled kickoffs as "TBD".
        if game.detail.uppercased().contains("TBD") { return "TBD" }
        return game.startTime.formatted(date: .omitted, time: .shortened)
    }
}
