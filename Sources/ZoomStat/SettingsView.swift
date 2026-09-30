import SwiftUI
import ZoomStatCore

struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        TabView {
            GeneralPane().tabItem { Label("General", systemImage: "gearshape") }
            MenuBarPane().tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }
            HealthPane().tabItem { Label("Health", systemImage: "waveform.path.ecg") }
            LoggingPane().tabItem { Label("Logging", systemImage: "doc.text") }
            AlertsPane().tabItem { Label("Alerts", systemImage: "bell") }
        }
        .frame(width: 560)
        .environmentObject(model)
    }
}

private struct GeneralPane: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Form {
            Picker("Refresh interval", selection: $model.settings.refreshInterval) {
                Text("0.5 s").tag(0.5); Text("1 s").tag(1.0); Text("2 s").tag(2.0); Text("5 s").tag(5.0)
            }
            Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))

            Section {
                Toggle("Read all Statistics tabs (Overall, Audio, Video, Screen sharing)", isOn: $model.settings.cycleTabs)
                Toggle("Also switch tabs while I am using the Statistics window", isOn: $model.settings.cycleTabsWhenVisible)
                    .disabled(!model.settings.cycleTabs)
                Toggle("Open Statistics minimized when a meeting starts", isOn: $model.settings.autoOpenStatistics)
            } header: {
                Text("Zoom Statistics window")
            } footer: {
                Text("ZoomStat reads Zoom's own Statistics panel through Accessibility. The window can stay minimized or in the background; ZoomStat only switches its tabs, and pauses while you are using it.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Permissions") {
                LabeledContent("Accessibility") {
                    HStack {
                        Text(model.stats.accessibilityGranted ? "Granted" : "Not granted").foregroundStyle(.secondary)
                        Button("Open Privacy Settings") { model.openAccessibilitySettings() }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct HealthPane: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Form {
            Picker("Judge quality by", selection: $model.settings.qualityDirection) {
                ForEach(QualityDirection.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Section {
                LimitRow(title: "Latency", unit: "ms", limit: $model.settings.thresholds.latencyMs)
                LimitRow(title: "Jitter", unit: "ms", limit: $model.settings.thresholds.jitterMs)
                LimitRow(title: "Packet loss", unit: "%", limit: $model.settings.thresholds.packetLossPercent)
                LimitRow(title: "Video FPS", unit: "fps", limit: $model.settings.thresholds.videoFPS, lowerIsWorse: true)
            } header: {
                Text("Thresholds")
            } footer: {
                Text("The worst enabled metric in the chosen direction decides the status: Healthy, Degraded or Poor. Alerts use the same direction. Unavailable when no meeting data is readable.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            LabeledContent("Current status") { HealthLabel(health: model.health) }
        }
        .formStyle(.grouped)
    }
}

private struct LimitRow: View {
    let title: String
    let unit: String
    @Binding var limit: Limit
    var lowerIsWorse = false
    var body: some View {
        HStack {
            Toggle(title, isOn: $limit.enabled)
            Spacer()
            Text(lowerIsWorse ? "Degraded ≤" : "Degraded ≥").foregroundStyle(.secondary)
            NumberField(value: $limit.degraded).disabled(!limit.enabled)
            Text(lowerIsWorse ? "Poor ≤" : "Poor ≥").foregroundStyle(.secondary)
            NumberField(value: $limit.poor).disabled(!limit.enabled)
            Text(unit).foregroundStyle(.secondary).frame(width: 26, alignment: .leading)
        }
    }
}

private struct NumberField: View {
    @Binding var value: Double
    var body: some View {
        TextField("", value: $value, format: .number.precision(.fractionLength(0...1)))
            .labelsHidden().multilineTextAlignment(.trailing).frame(width: 52)
    }
}

private struct LoggingPane: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Form {
            Section {
                Toggle("Log meeting statistics", isOn: $model.settings.loggingEnabled)
                Toggle("CSV", isOn: $model.settings.logCSV)
                Toggle("JSON (one object per line)", isOn: $model.settings.logJSON)
                LabeledContent("Location") {
                    Button("Show in Finder") { model.revealLogs() }
                }
            } footer: {
                Text("One file per meeting in ~/Library/Application Support/ZoomStat/Logs. Only technical connection and performance values are recorded — never participant names, chat, audio, video or meeting content.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AlertsPane: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Form {
            Toggle("Show notifications", isOn: $model.settings.notificationsEnabled)
            Section {
                ForEach($model.settings.alertRules) { $rule in
                    HStack {
                        Toggle(rule.metric.title, isOn: $rule.enabled)
                        Spacer()
                        Text(rule.metric.lowerIsWorse ? "below" : "above").foregroundStyle(.secondary)
                        NumberField(value: $rule.threshold)
                        Text(rule.metric.unit).foregroundStyle(.secondary).frame(width: 26, alignment: .leading)
                        Text("for").foregroundStyle(.secondary)
                        NumberField(value: $rule.sustainSeconds)
                        Text("s").foregroundStyle(.secondary)
                    }
                    .disabled(!model.settings.notificationsEnabled)
                }
            } header: {
                Text("Conditions")
            } footer: {
                Text("A notification is shown once when a condition holds for the whole duration, and again only after it has cleared.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Menu bar profiles

private struct MenuBarPane: View {
    @EnvironmentObject var model: AppModel
    @State private var selection: UUID?

    private var index: Int? {
        let id = selection ?? model.settings.activeProfile.id
        return model.settings.menuBarProfiles.firstIndex { $0.id == id }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                List(selection: $selection) {
                    ForEach(model.settings.menuBarProfiles) { p in
                        HStack {
                            Text(p.name)
                            Spacer()
                            if p.id == model.settings.activeProfile.id {
                                Image(systemName: "checkmark").foregroundStyle(.secondary)
                            }
                        }
                        .tag(p.id)
                    }
                }
                .listStyle(.bordered)
                .frame(width: 150, height: 260)
                HStack(spacing: 0) {
                    Button { addProfile() } label: { Image(systemName: "plus").frame(width: 22, height: 20) }
                    Button { removeProfile() } label: { Image(systemName: "minus").frame(width: 22, height: 20) }
                        .disabled(model.settings.menuBarProfiles.count <= 1)
                }
                .buttonStyle(.borderless)
                .padding(.top, 4)
            }

            if let i = index {
                ProfileEditor(profile: $model.settings.menuBarProfiles[i],
                              isActive: model.settings.menuBarProfiles[i].id == model.settings.activeProfile.id,
                              activate: { model.selectProfile(model.settings.menuBarProfiles[i].id) })
            }
        }
        .padding(20)
        .onAppear { if selection == nil { selection = model.settings.activeProfile.id } }
    }

    private func addProfile() {
        let p = MenuBarProfile(name: "New Profile", items: [.audioLatencyReceive])
        model.settings.menuBarProfiles.append(p)
        selection = p.id
    }

    private func removeProfile() {
        guard let i = index, model.settings.menuBarProfiles.count > 1 else { return }
        let removed = model.settings.menuBarProfiles.remove(at: i)
        if model.settings.activeProfileID == removed.id { model.settings.activeProfileID = nil }
        selection = model.settings.menuBarProfiles.first?.id
    }
}

private struct ProfileEditor: View {
    @EnvironmentObject var model: AppModel
    @Binding var profile: MenuBarProfile
    let isActive: Bool
    let activate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Name", text: $profile.name).frame(maxWidth: 180)
                Spacer()
                if isActive {
                    Text("In use").foregroundStyle(.secondary)
                } else {
                    Button("Use in Menu Bar", action: activate)
                }
            }
            Toggle("Show short labels (A = audio, V = video, ↑ send, ↓ receive)", isOn: $profile.showLabels)
            Toggle("Compact values (923k, 360p, 26fps) — keeps the item visible next to the notch", isOn: $profile.compact)

            Text("Shown in menu bar").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            VStack(spacing: 0) {
                if profile.items.isEmpty {
                    Text("Only the icon is shown.").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(6)
                }
                ForEach(Array(profile.items.enumerated()), id: \.offset) { i, item in
                    HStack {
                        Text("\(item.group.rawValue) – \(item.title)")
                        Spacer()
                        Button { move(i, -1) } label: { Image(systemName: "chevron.up") }.disabled(i == 0)
                        Button { move(i, 1) } label: { Image(systemName: "chevron.down") }.disabled(i == profile.items.count - 1)
                        Button { profile.items.remove(at: i) } label: { Image(systemName: "xmark") }
                    }
                    .buttonStyle(.borderless)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(i % 2 == 0 ? Color.primary.opacity(0.04) : .clear)
                }
            }
            .background(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.12)))

            Menu("Add Value") {
                ForEach(MenuBarItem.Group.allCases, id: \.self) { g in
                    Section(g.rawValue) {
                        ForEach(MenuBarItem.allCases.filter { $0.group == g }) { item in
                            Button(item.title) { profile.items.append(item) }
                                .disabled(profile.items.contains(item))
                        }
                    }
                }
            }
            .fixedSize()

            LabeledContent("Preview") {
                Text(profile.text(model.stats, health: model.health) ?? "Icon only")
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            Text("Audio send values are only reported while your microphone (or shared computer sound) is live.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func move(_ i: Int, _ d: Int) {
        let j = i + d
        guard profile.items.indices.contains(j) else { return }
        profile.items.swapAt(i, j)
    }
}
