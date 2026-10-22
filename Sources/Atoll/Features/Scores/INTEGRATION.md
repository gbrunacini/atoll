# Features/Scores — Integration

## Views

| View | Placement |
|---|---|
| `ScoresWidgetView` | Open notch, its own top-level **Scores** tab (`NotchTab.scores`, SF Symbol `sportscourt`; listed in `SettingsStore.visibleTabsCSV`'s default). Fills whatever frame it is given; content scrolls. One row per game: live first, then upcoming (with start time), then finals. Dark-notch styled. Right-click a row → "Open on ESPN". |
| `ScoreWing` | Closed-notch **right wing**, gated on `SettingsStore.scoresLiveActivity`. "CHI 98 – BOS 94 Q4" for a live tracked game; cycles every 8 s when several are live. Renders **nothing** when no tracked team is live, so it can be composed unconditionally. |
| `ScoresSettingsView` | Settings window, "Scores" pane. Team picker per league (NFL / NBA / MLB), poll intervals, wing toggle. Standard system `Form` styling. |

## Startup

In `AppDelegate.startManagers()`:

```swift
ScoresStore.shared.start()
```

This loads `scores.json` and starts polling (idempotent). The widget also calls `start()`
on appear, so the feature still works if this call is missing.

## Model / store

- `ScoresStore.shared` (`@MainActor ObservableObject`):
  - Published state: `games: [GameSummary]` (already ordered), `config`, `isRefreshing`,
    `lastUpdated`, `lastError`, `catalog`.
  - Derived: `liveGames`, `upcomingGames`, `finalGames`.
  - Methods: `addTeam`, `removeTeam`, `setLivePollSeconds`, `setIdlePollSeconds`,
    `refreshNow`, `refreshIfStale`, `loadCatalog`.
- `GameSummary`: `league`, `home` / `away` (`Side`: abbreviation, name, score, isTracked,
  isWinner), `status` (`.pre` / `.live` / `.final`), `clock`, `period`, `detail` (ESPN short
  status), `periodLabel` (compact, for the wing), `startTime`.
- Polling: every `livePollSeconds` (default 60 s) while a tracked game is live, otherwise
  `idlePollSeconds` (default 15 min). It also wakes at the next scheduled start, polls at the
  live rate while a started game is still "pre" on ESPN, retries within 2 min after a failure,
  and refreshes on system wake.

## Data source

ESPN's public site API (no key):

- `site.api.espn.com/apis/site/v2/sports/{football/nfl | basketball/nba | baseball/mlb}/scoreboard`:
  live and today's games (the whole week for NFL). One request per league that has a tracked team.
- `…/{league}/teams/{id}` → `team.nextEvent`: each team's next game, so upcoming games beyond
  today's board appear. Upcoming games more than 7 days out are hidden.
- `…/{league}/teams`: full team list for the settings picker, fetched once per session.

Date-range scoreboard queries (`?dates=A-B`) return HTTP 400, so don't use them. Event dates
have no seconds (`2026-10-23T00:15Z`). `score` is a string on scoreboards and an object on team pages.

## Persistence

`~/Library/Application Support/Atoll/scores.json` holds the tracked teams and both poll
intervals (pretty-printed; missing keys fall back to defaults). A corrupt file is renamed to
`scores.json.corrupt`. Defaults: Chicago Bears (NFL), Boston Red Sox (MLB), Chicago Bulls and
Boston Celtics (NBA).

## Settings keys (`@AppStorage`)

- `scoresLiveActivity` (Bool, default true): show the closed-notch wing. Declared in
  `SettingsStore` alongside the other live-activity toggles, and bound directly in
  `ScoresSettingsView` (same key, as `SystemEventsSettingsView` does for battery).

## Permissions / Info.plist

None. The app is unsandboxed; outbound HTTPS only.
