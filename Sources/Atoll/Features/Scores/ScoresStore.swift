import AppKit
import SwiftUI
import Combine

// MARK: - Model

/// A league Atoll can follow, with its ESPN API path.
enum SportsLeague: String, Codable, CaseIterable, Identifiable {
    case nfl, nba, mlb

    var id: String { rawValue }

    var displayName: String { rawValue.uppercased() }

    /// Path segment under `site.api.espn.com/apis/site/v2/sports/`.
    var espnPath: String {
        switch self {
        case .nfl: return "football/nfl"
        case .nba: return "basketball/nba"
        case .mlb: return "baseball/mlb"
        }
    }

    var systemImage: String {
        switch self {
        case .nfl: return "football.fill"
        case .nba: return "basketball.fill"
        case .mlb: return "baseball.fill"
        }
    }
}

/// A team identified by its ESPN id within a league.
struct SportsTeam: Codable, Hashable, Identifiable {
    let league: SportsLeague
    let teamID: String
    let abbreviation: String
    let displayName: String

    var id: String { "\(league.rawValue):\(teamID)" }
}

/// One game involving a tracked team, flattened from ESPN's scoreboard JSON.
struct GameSummary: Identifiable, Equatable {
    enum Status: String {
        case pre, live, final

        /// Display order: live, then upcoming, then finals.
        var sortRank: Int {
            switch self {
            case .live: return 0
            case .pre: return 1
            case .final: return 2
            }
        }
    }

    struct Side: Equatable {
        let teamID: String
        let abbreviation: String
        /// Short name, e.g. "Bulls".
        let name: String
        /// nil before the game starts.
        let score: Int?
        let isTracked: Bool
        let isWinner: Bool
    }

    /// `<league>:<ESPN event id>`.
    let id: String
    let eventID: String
    let league: SportsLeague
    let home: Side
    let away: Side
    let status: Status
    /// Game clock ("4:12", "45.4"), live basketball/football only.
    let clock: String?
    let period: Int
    /// ESPN's short status: "4:12 - 3rd", "Top 5th", "Halftime", "Final/OT".
    let detail: String
    /// Compact period for the closed-notch wing: "Q4", "OT", "HT", "▲5".
    let periodLabel: String
    let startTime: Date

    var espnURL: URL? {
        URL(string: "https://www.espn.com/\(league.rawValue)/game/_/gameId/\(eventID)")
    }
}

/// User configuration, persisted to `scores.json`.
struct ScoresConfig: Codable, Equatable {
    var teams: [SportsTeam]
    /// Poll interval while any tracked game is live.
    var livePollSeconds: Double
    /// Poll interval otherwise.
    var idlePollSeconds: Double

    static let `default` = ScoresConfig(
        teams: [
            SportsTeam(league: .nfl, teamID: "3", abbreviation: "CHI", displayName: "Chicago Bears"),
            SportsTeam(league: .mlb, teamID: "2", abbreviation: "BOS", displayName: "Boston Red Sox"),
            SportsTeam(league: .nba, teamID: "4", abbreviation: "CHI", displayName: "Chicago Bulls"),
            SportsTeam(league: .nba, teamID: "2", abbreviation: "BOS", displayName: "Boston Celtics")
        ],
        livePollSeconds: 60,
        idlePollSeconds: 15 * 60
    )
}

extension ScoresConfig {
    /// Missing keys fall back to defaults so older files keep loading.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        teams = try container.decodeIfPresent([SportsTeam].self, forKey: .teams) ?? Self.default.teams
        livePollSeconds = try container.decodeIfPresent(Double.self, forKey: .livePollSeconds)
            ?? Self.default.livePollSeconds
        idlePollSeconds = try container.decodeIfPresent(Double.self, forKey: .idlePollSeconds)
            ?? Self.default.idlePollSeconds
    }
}

// MARK: - Store

/// Polls ESPN's public scoreboard for the tracked teams: every
/// `livePollSeconds` while one of their games is live, `idlePollSeconds`
/// otherwise. Configuration is persisted in Application Support.
@MainActor
final class ScoresStore: ObservableObject {
    static let shared = ScoresStore()

    /// Tracked teams' games: live first, then upcoming (soonest first),
    /// then finals (most recent first).
    @Published private(set) var games: [GameSummary] = []
    @Published private(set) var config: ScoresConfig
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var lastError: String?
    /// Every team per league, for the settings picker. Fetched on demand.
    @Published private(set) var catalog: [SportsLeague: [SportsTeam]] = [:]

    /// Upcoming games further out than this are hidden.
    private let upcomingHorizon: TimeInterval = 7 * 24 * 3600

    // MARK: Derived

    var liveGames: [GameSummary] { games.filter { $0.status == .live } }
    var upcomingGames: [GameSummary] { games.filter { $0.status == .pre } }
    var finalGames: [GameSummary] { games.filter { $0.status == .final } }

    func teams(in league: SportsLeague) -> [SportsTeam] {
        config.teams.filter { $0.league == league }
    }

    func isTracked(_ team: SportsTeam) -> Bool {
        config.teams.contains { $0.id == team.id }
    }

    // MARK: Mutations

    func addTeam(_ team: SportsTeam) {
        guard !isTracked(team) else { return }
        config.teams.append(team)
        save()
        refreshNow()
    }

    func removeTeam(_ team: SportsTeam) {
        config.teams.removeAll { $0.id == team.id }
        save()
        let tracked = Set(config.teams.map(\.id))
        games.removeAll { game in
            !tracked.contains("\(game.league.rawValue):\(game.home.teamID)")
                && !tracked.contains("\(game.league.rawValue):\(game.away.teamID)")
        }
    }

    func setLivePollSeconds(_ seconds: Double) {
        config.livePollSeconds = seconds
        save()
        if !isRefreshing { scheduleNextPoll() }
    }

    func setIdlePollSeconds(_ seconds: Double) {
        config.idlePollSeconds = seconds
        save()
        if !isRefreshing { scheduleNextPoll() }
    }

    // MARK: Polling

    private var started = false
    private var pollTask: Task<Void, Never>?

    /// Starts polling. Idempotent.
    func start() {
        guard !started else { return }
        started = true
        // Scores go stale over sleep; catch up as soon as the Mac wakes.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshNow()
            }
        }
        refreshNow()
    }

    func refreshNow() {
        Task { await refresh() }
    }

    /// Refreshes when the data is older than the live poll interval,
    /// e.g. when the Scores pane appears.
    func refreshIfStale() {
        if let lastUpdated, Date().timeIntervalSince(lastUpdated) < config.livePollSeconds { return }
        refreshNow()
    }

    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer {
            isRefreshing = false
            scheduleNextPoll()
        }

        let teams = config.teams
        guard !teams.isEmpty else {
            games = []
            lastError = nil
            return
        }

        // One scoreboard per league (live clocks, today's games, the NFL week)
        // plus each team's next event, so upcoming games beyond today show too.
        let fetches = await withTaskGroup(of: ESPNFetch.self) { group -> [ESPNFetch] in
            for league in Set(teams.map(\.league)) {
                group.addTask {
                    ESPNFetch(league: league, isScoreboard: true,
                              events: try? await ESPNClient.scoreboard(league))
                }
            }
            for team in teams {
                group.addTask {
                    ESPNFetch(league: team.league, isScoreboard: false,
                              events: try? await ESPNClient.nextEvents(team))
                }
            }
            var results: [ESPNFetch] = []
            for await fetch in group { results.append(fetch) }
            return results
        }

        guard fetches.contains(where: { $0.events != nil }) else {
            lastError = "Can't reach ESPN"
            return
        }

        let tracked = Set(teams.map(\.id))
        var byID: [String: GameSummary] = [:]
        // Scoreboards first: they carry live clocks; next-event copies only fill gaps.
        for fetch in fetches.sorted(by: { $0.isScoreboard && !$1.isScoreboard }) {
            for event in fetch.events ?? [] {
                guard let game = GameSummary(event: event, league: fetch.league, tracked: tracked),
                      byID[game.id] == nil else { continue }
                byID[game.id] = game
            }
        }
        // Keep the last known games for a league whose scoreboard failed this round.
        let failedLeagues = Set(fetches.filter { $0.isScoreboard && $0.events == nil }.map(\.league))
        for game in games where failedLeagues.contains(game.league) && byID[game.id] == nil {
            byID[game.id] = game
        }

        let now = Date()
        let visible = byID.values.filter { $0.status != .pre || $0.startTime <= now.addingTimeInterval(upcomingHorizon) }
        let ordered = visible.sorted { a, b in
            if a.status != b.status { return a.status.sortRank < b.status.sortRank }
            return a.status == .final ? a.startTime > b.startTime : a.startTime < b.startTime
        }
        if ordered != games { games = ordered }
        lastUpdated = now
        lastError = nil
    }

    private func scheduleNextPoll() {
        pollTask?.cancel()
        guard started else { return }
        let delay = nextPollDelay()
        pollTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    private func nextPollDelay() -> TimeInterval {
        let live = max(15, config.livePollSeconds)
        let idle = max(60, config.idlePollSeconds)
        if games.contains(where: { $0.status == .live }) { return live }

        // A game that should have started but isn't live on ESPN yet: poll at
        // the live cadence until it flips. Otherwise wake up for the next start.
        let now = Date()
        let untilStart = games.filter { $0.status == .pre }.map { $0.startTime.timeIntervalSince(now) }
        if untilStart.contains(where: { $0 <= 0 && $0 > -3 * 3600 }) { return live }
        var delay = idle
        if let next = untilStart.filter({ $0 > 0 }).min() {
            delay = min(delay, max(live, next))
        }
        // Retry sooner after a failed round.
        if lastError != nil { delay = min(delay, 120) }
        return delay
    }

    // MARK: Team catalog

    private var catalogRequests: Set<SportsLeague> = []

    /// Loads the league's team list for the settings picker, once per session.
    func loadCatalog(_ league: SportsLeague) {
        guard catalog[league] == nil, !catalogRequests.contains(league) else { return }
        catalogRequests.insert(league)
        Task {
            let teams = try? await ESPNClient.teams(league)
            catalogRequests.remove(league)
            if let teams {
                catalog[league] = teams.sorted { $0.displayName < $1.displayName }
            }
        }
    }

    // MARK: Persistence

    private let fileURL: URL

    private init() {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        let dir = base.appendingPathComponent("Atoll", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("scores.json")

        config = .default
        if !load() { save() }
    }

    /// Returns false when there was no file to load.
    private func load() -> Bool {
        guard let data = try? Data(contentsOf: fileURL) else { return false }
        do {
            config = try JSONDecoder().decode(ScoresConfig.self, from: data)
        } catch {
            NSLog("Atoll Scores: failed to decode scores.json (%@); backing it up and using defaults",
                  String(describing: error))
            let backup = fileURL.appendingPathExtension("corrupt")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: fileURL, to: backup)
        }
        return true
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(config)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Atoll Scores: save failed: %@", String(describing: error))
        }
    }
}

// MARK: - ESPN

/// Minimal client for ESPN's public site API (no key required).
private enum ESPNClient {
    static func scoreboard(_ league: SportsLeague) async throws -> [ESPNEvent] {
        try await get(ESPNScoreboard.self, "\(league.espnPath)/scoreboard").events ?? []
    }

    static func nextEvents(_ team: SportsTeam) async throws -> [ESPNEvent] {
        try await get(ESPNTeamPage.self, "\(team.league.espnPath)/teams/\(team.teamID)").team.nextEvent ?? []
    }

    static func teams(_ league: SportsLeague) async throws -> [SportsTeam] {
        let page = try await get(ESPNTeamsPage.self, "\(league.espnPath)/teams")
        return page.sports.flatMap(\.leagues).flatMap(\.teams).compactMap { entry in
            guard let abbreviation = entry.team.abbreviation,
                  let displayName = entry.team.displayName else { return nil }
            return SportsTeam(league: league, teamID: entry.team.id,
                              abbreviation: abbreviation, displayName: displayName)
        }
    }

    private static func get<T: Decodable>(_ type: T.Type, _ path: String) async throws -> T {
        guard let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/\(path)") else {
            throw URLError(.badURL)
        }
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

/// One request's events, tagged with where they came from.
private struct ESPNFetch {
    let league: SportsLeague
    let isScoreboard: Bool
    /// nil when the request failed.
    let events: [ESPNEvent]?
}

private struct ESPNScoreboard: Decodable {
    let events: [ESPNEvent]?
}

private struct ESPNTeamPage: Decodable {
    struct Team: Decodable {
        let nextEvent: [ESPNEvent]?
    }
    let team: Team
}

private struct ESPNTeamsPage: Decodable {
    struct Sport: Decodable { let leagues: [League] }
    struct League: Decodable { let teams: [Entry] }
    struct Entry: Decodable { let team: ESPNTeam }
    let sports: [Sport]
}

private struct ESPNEvent: Decodable {
    let id: String
    /// "2026-10-23T00:15Z" — ISO 8601 without seconds.
    let date: String
    let competitions: [ESPNCompetition]
}

private struct ESPNCompetition: Decodable {
    let competitors: [ESPNCompetitor]
    let status: ESPNStatus?
}

private struct ESPNCompetitor: Decodable {
    let homeAway: String
    let winner: Bool?
    let team: ESPNTeam
    let score: ESPNScore?
}

private struct ESPNTeam: Decodable {
    let id: String
    let abbreviation: String?
    let displayName: String?
    let shortDisplayName: String?
}

/// Scoreboards send `"score": "98"`; team pages send `{"value": 98.0, "displayValue": "98"}`.
private struct ESPNScore: Decodable {
    let value: Int?

    init(from decoder: Decoder) throws {
        struct Object: Decodable {
            let value: Double?
            let displayValue: String?
        }
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = Int(string)
        } else if let number = try? container.decode(Double.self) {
            value = Int(number)
        } else {
            let object = try container.decode(Object.self)
            value = object.value.map { Int($0) } ?? object.displayValue.flatMap { Int($0) }
        }
    }
}

private struct ESPNStatus: Decodable {
    struct Kind: Decodable {
        /// e.g. "STATUS_IN_PROGRESS", "STATUS_HALFTIME", "STATUS_END_PERIOD".
        let name: String?
        /// "pre" | "in" | "post"
        let state: String
        let shortDetail: String?
        let detail: String?
    }
    let displayClock: String?
    let period: Int?
    let type: Kind
}

private enum ESPNDate {
    private static let formatters: [DateFormatter] = ["yyyy-MM-dd'T'HH:mmX", "yyyy-MM-dd'T'HH:mm:ssX"].map { format in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = format
        return formatter
    }

    static func parse(_ string: String) -> Date? {
        for formatter in formatters {
            if let date = formatter.date(from: string) { return date }
        }
        return nil
    }
}

private extension GameSummary {
    /// nil when the event is malformed or involves none of the tracked teams.
    init?(event: ESPNEvent, league: SportsLeague, tracked: Set<String>) {
        guard let competition = event.competitions.first,
              let homeEntry = competition.competitors.first(where: { $0.homeAway == "home" }),
              let awayEntry = competition.competitors.first(where: { $0.homeAway == "away" }),
              let startTime = ESPNDate.parse(event.date)
        else { return nil }

        let homeTracked = tracked.contains("\(league.rawValue):\(homeEntry.team.id)")
        let awayTracked = tracked.contains("\(league.rawValue):\(awayEntry.team.id)")
        guard homeTracked || awayTracked else { return nil }

        let kind = competition.status?.type
        let status: Status
        switch kind?.state {
        case "in": status = .live
        case "post": status = .final
        default: status = .pre
        }
        let period = competition.status?.period ?? 0
        let detail = kind?.shortDetail ?? kind?.detail ?? ""

        self.init(
            id: "\(league.rawValue):\(event.id)",
            eventID: event.id,
            league: league,
            home: Self.side(homeEntry, tracked: homeTracked, status: status),
            away: Self.side(awayEntry, tracked: awayTracked, status: status),
            status: status,
            clock: status == .live && league != .mlb ? competition.status?.displayClock : nil,
            period: period,
            detail: detail,
            periodLabel: Self.periodLabel(league: league, period: period, statusName: kind?.name, detail: detail),
            startTime: startTime
        )
    }

    static func side(_ entry: ESPNCompetitor, tracked: Bool, status: Status) -> Side {
        let abbreviation = entry.team.abbreviation ?? "—"
        return Side(
            teamID: entry.team.id,
            abbreviation: abbreviation,
            name: entry.team.shortDisplayName ?? entry.team.displayName ?? abbreviation,
            score: status == .pre ? nil : entry.score?.value,
            isTracked: tracked,
            isWinner: entry.winner ?? false
        )
    }

    /// "Q4", "OT", "2OT", "HT", "End Q1" for football/basketball;
    /// "▲5", "▼5", "Mid 5", "End 5" for baseball.
    static func periodLabel(league: SportsLeague, period: Int, statusName: String?, detail: String) -> String {
        if league == .mlb {
            let lower = detail.lowercased()
            if lower.hasPrefix("top") { return "▲\(period)" }
            if lower.hasPrefix("bot") { return "▼\(period)" }
            if lower.hasPrefix("mid") { return "Mid \(period)" }
            if lower.hasPrefix("end") { return "End \(period)" }
            return detail
        }
        if statusName == "STATUS_HALFTIME" { return "HT" }
        let base: String
        switch period {
        case 1...4: base = "Q\(period)"
        case 5: base = "OT"
        case 6...: base = "\(period - 4)OT"
        default: return detail
        }
        return statusName == "STATUS_END_PERIOD" ? "End \(base)" : base
    }
}
