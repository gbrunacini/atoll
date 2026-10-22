# Atoll — notes for Claude

NotchNook-style notch hub for macOS 14+. SPM executable target (`Sources/Atoll`),
Swift 5 language mode, unsandboxed. Full module contract: `docs/DESIGN.md`.

- Build: `./scripts/build-app.sh` → `dist/Atoll.app`
- Relaunch: `pkill -x Atoll; open dist/Atoll.app`
- Remotes: `origin` = your fork, `upstream` = rutmehta/atoll

## Feature pattern

Each feature is a folder under `Sources/Atoll/Features/<Name>/`. `Features/Todos` is the
reference implementation; copy its shape:

| File | Role |
|---|---|
| `<Name>Store.swift` | `@MainActor final class … : ObservableObject` with `static let shared` and a `private init()`. Owns state (`@Published private(set)`), derived computed properties, mutation methods, timers, and JSON persistence in `~/Library/Application Support/Atoll/<name>.json` (atomic writes; a corrupt file is renamed `.corrupt`). |
| `<Name>WidgetView.swift` | Open-notch pane. Dark-notch styling: white text at layered opacities (≈0.92 primary, 0.45 secondary, 0.3 hint), 12.5 pt rows, `white.opacity(0.06)` hover fill, 8–9 pt corner radii. Fills whatever frame it is given (`maxWidth/maxHeight: .infinity`, top-leading). Observes `<Name>Store.shared`. |
| `<Name>Wing.swift` | Compact closed-notch live activity, `frame(maxHeight: .infinity)`. Renders **nothing** when there is nothing to show, so it can be composed unconditionally. |
| `<Name>SettingsView.swift` | Standard system `Form` with `.formStyle(.grouped)` — the settings window is a normal window, not dark-forced. Feature keys use `@AppStorage("<name>.<key>")`. |
| `INTEGRATION.md` | Views + placement, startup calls, settings view, persistence, settings keys, permissions. |

Features reference only Core types and Apple frameworks, never another feature.

## The 5 wiring points

Hooking a feature into the app touches exactly these files (grep `Todos` for examples):

1. **`UI/OpenNotchView.swift`**: add a `ToolPane` case (raw value = rail label) with its
   `systemImage`, and a branch in `toolContent`. For a top-level tab instead (as Scores is),
   add a `NotchTab` case in `Core/NotchViewModel.swift`, include it in the default of
   `SettingsStore.visibleTabsCSV`, and branch in `content`.
2. **`UI/ClosedNotchView.swift`**: add the wing to the `rightWing` `HStack`, gated on
   `settings.<name>LiveActivity`.
3. **`UI/SettingsRootView.swift`**: add a `Pane` case + `systemImage` + `paneContent` branch,
   and a toggle in `LiveActivitySettingsView`.
4. **`Core/SettingsStore.swift`**: add
   `@AppStorage("<name>LiveActivity") var <name>LiveActivity = true { willSet { objectWillChange.send() } }`
   under `// MARK: Live activities`.
5. **`App/AppDelegate.swift`**: start or warm the store in `startManagers()`, and stop or flush it in
   `applicationWillTerminate` if it needs to.

Also add `"Features/<Name>/INTEGRATION.md"` to the `exclude:` list in `Package.swift`, or SPM
warns about an unhandled file.

## Rules

- Every new feature gets its own `Features/<Name>/` folder **and** an `INTEGRATION.md`.
- **Never refactor outside the feature folder and the 5 wiring points** (plus the one
  `Package.swift` exclude line). Leave `Core/*`, `scripts/*` and other features alone. In
  `SettingsStore`, add the key and nothing else.
- Annotate UI-facing classes `@MainActor`; avoid strict-concurrency-only idioms (Swift 5 mode).
- Build with `./scripts/build-app.sh` and fix every warning in files you touched.
- `docs/DESIGN.md` mentions `/Users/rutmehta/...` paths and "do not run git". Those were for
  the original multi-agent build; use this repo root and normal git here.
