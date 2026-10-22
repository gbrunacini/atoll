import SwiftUI

/// Settings pane for the Scores widget; the integrator adds it as a
/// section/tab of the settings window. Uses standard system styling
/// (the settings window is a normal light/dark window, not the notch).
struct ScoresSettingsView: View {
    @ObservedObject private var store = ScoresStore.shared
    // "scoresLiveActivity" is the shared toggle also exposed by
    // SettingsStore / LiveActivitySettingsView — same UserDefaults key on purpose.
    @AppStorage("scoresLiveActivity") private var showWing = true

    var body: some View {
        Form {
            ForEach(SportsLeague.allCases) { league in
                Section(league.displayName) {
                    let tracked = store.teams(in: league)
                    if tracked.isEmpty {
                        Text("No teams")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(tracked) { team in
                        HStack {
                            Text(team.displayName)
                            Spacer()
                            Button {
                                store.removeTeam(team)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .help("Stop following \(team.displayName)")
                        }
                    }
                    addTeamMenu(for: league)
                }
            }

            Section {
                Picker("While a game is live", selection: livePollBinding) {
                    Text("Every 30 seconds").tag(30.0)
                    Text("Every minute").tag(60.0)
                    Text("Every 2 minutes").tag(120.0)
                    Text("Every 5 minutes").tag(300.0)
                }
                Picker("Otherwise", selection: idlePollBinding) {
                    Text("Every 5 minutes").tag(300.0)
                    Text("Every 15 minutes").tag(900.0)
                    Text("Every 30 minutes").tag(1800.0)
                    Text("Every hour").tag(3600.0)
                }
            } header: {
                Text("Refresh")
            } footer: {
                Text("Atoll also checks right around each scheduled start, so games go live on time. Scores come from ESPN.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Closed notch") {
                Toggle("Show live score next to the notch", isOn: $showWing)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            for league in SportsLeague.allCases {
                store.loadCatalog(league)
            }
        }
    }

    private func addTeamMenu(for league: SportsLeague) -> some View {
        let catalog = store.catalog[league]
        let available = (catalog ?? []).filter { !store.isTracked($0) }
        return Menu(catalog == nil ? "Loading teams…" : "Add Team…") {
            ForEach(available) { team in
                Button(team.displayName) { store.addTeam(team) }
            }
        }
        .disabled(available.isEmpty)
    }

    private var livePollBinding: Binding<Double> {
        Binding(get: { store.config.livePollSeconds }, set: { store.setLivePollSeconds($0) })
    }

    private var idlePollBinding: Binding<Double> {
        Binding(get: { store.config.idlePollSeconds }, set: { store.setIdlePollSeconds($0) })
    }
}
