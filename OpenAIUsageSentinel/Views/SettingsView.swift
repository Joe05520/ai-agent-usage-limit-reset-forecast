import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var store: SentinelStore
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var loginMessage: String?
    @State private var showManual = false
    private func stageRange(_ index: Int) -> ClosedRange<Double> {
        let stages = store.settings.reminders.stages
        let lower = index + 1 < stages.count ? stages[index + 1] + 1 : 0
        let upper = index > 0 ? stages[index - 1] - 1 : 99
        return lower...max(lower, upper)
    }
    var body: some View {
        Form {
            Section(L10n.t("General")) {
                Picker(L10n.t("Language"), selection: $store.settings.language) {
                    ForEach(AppLanguage.allCases) { language in Text(language.label).tag(language) }
                }
                Text(L10n.t("Language changes immediately. Source posts remain in their original language.")).font(.caption).foregroundStyle(.secondary)
                Toggle(L10n.t("Launch at Login"), isOn: $loginEnabled).onChange(of: loginEnabled) { _, enabled in
                    do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; loginMessage = SMAppService.mainApp.status == .requiresApproval ? L10n.t("Approval required in System Settings → Login Items.") : nil }
                    catch { loginMessage = error.localizedDescription; loginEnabled = SMAppService.mainApp.status == .enabled }
                }
                if let loginMessage { Text(loginMessage).font(.caption).foregroundStyle(.orange) }
            }
            Section(L10n.t("Menu Bar Appearance")) {
                Picker(L10n.t("Display style"), selection: $store.settings.appearance.style) {
                    ForEach(MenuBarStyle.allCases) { style in Text(style.label).tag(style) }
                }
                if store.settings.appearance.style == .singleQuota {
                    if let usage = store.usage, !usage.buckets.isEmpty {
                        Picker(L10n.t("Displayed quota"), selection: Binding(get: { store.settings.appearance.selectedBucketID ?? "" }, set: { store.settings.appearance.selectedBucketID = $0.isEmpty ? nil : $0 })) {
                            Text(L10n.t("First available quota")).tag("")
                            ForEach(usage.buckets) { bucket in Text("\(bucket.product) · \(L10n.t(bucket.name))").tag(bucket.id) }
                        }
                    } else { Text(L10n.t("Quota choices will appear after a successful usage refresh.")).font(.caption).foregroundStyle(.secondary) }
                }
                Toggle(L10n.t("Show weekly quota"), isOn: $store.settings.showWeekly)
                    .disabled(store.settings.appearance.style == .singleQuota || store.settings.appearance.style == .icon)
                Toggle(L10n.t("Show short-window quota"), isOn: $store.settings.showShort)
                    .disabled(store.settings.appearance.style == .singleQuota || store.settings.appearance.style == .icon)
                Toggle(L10n.t("Show reset signal count in menu bar"), isOn: $store.settings.appearance.showSignalCount)
                Toggle(L10n.t("Show available banked reset credits in popover"), isOn: $store.settings.appearance.showBankedCredits)
                LabeledContent(L10n.t("Preview")) {
                    Text(MenuBarDisplay.title(usage: store.usageAvailable ? store.usage : MenuBarDisplay.previewUsage, available: true, signalCount: store.usageAvailable ? store.activeEvents.count : 1, settings: store.settings))
                        .font(.system(.body, design: .monospaced)).textSelection(.enabled)
                }
                Text(store.settings.appearance.style.explanation).font(.caption).foregroundStyle(.secondary)
                if store.settings.appearance.style == .percentages {
                    let previewUsage = store.usageAvailable ? store.usage : MenuBarDisplay.previewUsage
                    if let previewUsage {
                        Text(L10n.t("Order: ") + MenuBarDisplay.buckets(previewUsage, settings: store.settings).map { "\($0.product) \(L10n.t($0.name))" }.joined(separator: " / ")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(L10n.t(store.usageAvailable ? "Preview uses your latest quota. ⚡ counts current signals, not completed resets. These switches do not change detection or notifications." : "Illustrative preview only · 72% / 61% are sample values. These switches do not change detection or notifications."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L10n.t("Refresh")) {
                intervalPicker("Usage", selection: $store.settings.usageInterval)
                intervalPicker("Signals", selection: $store.settings.signalInterval)
            }
            Section(L10n.t("Remaining quota reminders")) {
                Toggle(L10n.t("Remind me when quota runs low"), isOn: $store.settings.reminders.enabled)
                ForEach(Array(store.settings.reminders.stages.enumerated()), id: \.offset) { index, percent in
                    HStack {
                        Stepper(L10n.f("Stage %d: ≤%d%% remaining", index + 1, Int(percent)), value: Binding(get: {
                            store.settings.reminders.stages.indices.contains(index) ? store.settings.reminders.stages[index] : percent
                        }, set: { value in
                            var stages = store.settings.reminders.stages
                            guard stages.indices.contains(index) else { return }
                            stages[index] = value; store.settings.reminders.stages = stages
                        }), in: stageRange(index)).disabled(!store.settings.reminders.enabled)
                        Button { var stages = store.settings.reminders.stages; stages.remove(at: index); store.settings.reminders.stages = stages } label: {
                            Image(systemName: "minus.circle")
                        }.buttonStyle(.borderless).accessibilityLabel(L10n.f("Remove stage %d", index + 1)).disabled(!store.settings.reminders.enabled)
                    }
                }
                Button(L10n.f("Add reminder (%d/5)", store.settings.reminders.stages.count)) { store.settings.reminders.addStage() }
                    .disabled(!store.settings.reminders.enabled || store.settings.reminders.stages.count >= UsageReminderSettings.maximumStages)
                Text(L10n.t("Add up to five distinct thresholds from 0–99%. Stages run from highest to lowest; the final stage is critical when more than one is set.")).font(.caption).foregroundStyle(.secondary)
                if let usage = store.usage {
                    ForEach(usage.buckets) { bucket in
                        Toggle("\(bucket.product) · \(L10n.t(bucket.name))", isOn: Binding(get: { !store.settings.reminders.excludedBucketIDs.contains(bucket.id) }, set: { enabled in
                            if enabled { store.settings.reminders.excludedBucketIDs.remove(bucket.id) } else { store.settings.reminders.excludedBucketIDs.insert(bucket.id) }
                        })).disabled(!store.settings.reminders.enabled)
                    }
                }
                if let until = store.settings.reminders.snoozedUntil, until > Date() {
                    LabeledContent(L10n.t("Paused until"), value: until.localizedFormatted(date: .omitted, time: .shortened))
                    Button(L10n.t("Resume Quota Reminders")) { store.resumeReminders() }
                } else { Button(L10n.t("Pause Quota Reminders for 1 Hour")) { store.snoozeReminders() }.disabled(!store.settings.reminders.enabled) }
                Toggle(L10n.t("Show observed consumption today"), isOn: $store.settings.reminders.showDailyTrend)
                Text(L10n.t("One reminder per stage per quota cycle. If several stages are crossed together, one alert covers them all. Existing low quota triggers on the next successful refresh. Reset alerts remain active while quota reminders are paused.")).font(.caption).foregroundStyle(.secondary)
            }
            Section(L10n.t("Notifications")) {
                Toggle(L10n.t("Unexpected personal reset"), isOn: $store.settings.notifyUnexpected)
                Toggle(L10n.t("Reset early signals"), isOn: $store.settings.notifyEarly)
                Toggle(L10n.t("Likely reset"), isOn: $store.settings.notifyLikely)
                Toggle(L10n.t("Official confirmation"), isOn: $store.settings.notifyOfficial)
                Picker(L10n.t("Notify confidence"), selection: $store.settings.threshold) {
                    Text(L10n.t("Very Early ≥15%")).tag(0.15); Text(L10n.t("Early ≥25%")).tag(0.25); Text(L10n.t("Likely ≥60%")).tag(0.60); Text(L10n.t("Official Only ≥90%")).tag(0.90)
                }
                LabeledContent(L10n.t("Permission"), value: L10n.t(store.permission))
                HStack {
                    Button(L10n.t("Enable Notifications")) { Task { _ = await store.notifications.requestPermission(); store.permission = await store.notifications.authorization() } }
                    Button(L10n.t("Send Test")) { Task { do { try await store.notifications.test() } catch { store.errorMessage = error.localizedDescription } } }
                }
            }
            Section(L10n.t("Sources")) {
                Toggle(L10n.t("OpenAI official"), isOn: $store.settings.official)
                Toggle(L10n.t("GitHub · openai/codex"), isOn: $store.settings.github)
                Toggle(L10n.t("Reddit · r/codex"), isOn: $store.settings.reddit)
                Toggle(L10n.t("Hacker News"), isOn: $store.settings.hackerNews)
                Text(L10n.t("X: unavailable until an authorized API/feed is configured. GitHub Discussions and other communities can be added as adapters.")).font(.caption).foregroundStyle(.secondary)
            }
            Section(L10n.t("Usage provider")) {
                Picker(L10n.t("AI agent"), selection: $store.settings.selectedAgent) {
                    ForEach(AgentKind.allCases) { agent in Text(agent.label).tag(agent) }
                }.onChange(of: store.settings.selectedAgent) { _, _ in
                    store.usageAvailable = false; store.settings.manualMode = false
                    Task { await store.refreshUsage(force: true) }
                }
                if store.settings.selectedAgent != .codex {
                    TextField(L10n.t("Local usage JSON path"), text: $store.settings.selectedExportPath)
                    Button(L10n.t("Choose JSON Export…")) {
                        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK, let url = panel.url { store.settings.selectedExportPath = url.path; Task { await store.refreshUsage(force: true) } }
                    }
                    Text(L10n.t("Claude supports the official status-line bridge. Gemini and Grok use a user-provided local export or manual snapshot. No cookies or private APIs are accessed. Files older than ten minutes are marked stale.")).font(.caption).foregroundStyle(.secondary)
                    Link(L10n.t("Agent setup guide"), destination: URL(string: "https://github.com/Joe05520/usage-sentinel/blob/main/docs/AGENTS.md")!)
                }
                TextField(L10n.t("Codex executable (optional)"), text: $store.settings.cliPath)
                Toggle(L10n.t("Use manual snapshot"), isOn: $store.settings.manualMode)
                Button(L10n.t("Enter Manual Snapshot…")) { showManual = true }
                Text(L10n.t("Codex windows are returned by the official local app-server. Other personal ChatGPT quotas are displayed only when the provider returns them.")).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(L10n.t("Record Banked Reset")) { store.recordIntent(.banked) }
                    Button(L10n.t("Record Purchased Reset")) { store.recordIntent(.purchased) }
                }
                Text(L10n.t("Record only when you apply a reset outside Sentinel. Annotation lasts 30 minutes; Sentinel never buys or consumes a reset.")).font(.caption).foregroundStyle(.secondary)
            }
            Section(L10n.t("Updates")) {
                Toggle(L10n.t("Check for updates daily"), isOn: Binding(get: { store.settings.automaticUpdateChecks != false }, set: { store.settings.automaticUpdateChecks = $0; store.saveSettings() }))
                Toggle(L10n.t("Include preview releases"), isOn: Binding(get: { store.settings.includePreviewUpdates != false }, set: { store.settings.includePreviewUpdates = $0; store.saveSettings() }))
                HStack {
                    Button(L10n.t("Check for Updates")) { Task { await store.checkUpdates() } }.disabled(store.updateBusy || store.isMock)
                    if store.updateManifest != nil { Button(L10n.t("Download Verified Update")) { Task { await store.downloadUpdate() } }.disabled(store.updateBusy) }
                }
                Text(store.updateStatus).font(.caption).textSelection(.enabled)
                Text(L10n.t("Downloads require an Ed25519 signature and SHA-256 match. Installation is manual; account data stays in Application Support.")).font(.caption).foregroundStyle(.secondary)
            }
            Section(L10n.t("Optional anonymous analytics")) {
                Toggle(L10n.t("Share anonymous daily usage habits"), isOn: $store.settings.analytics.enabled).disabled(store.isMock || ServiceConfiguration.bundled.telemetryURL == nil)
                Toggle(L10n.t("Also share coarse remaining-quota bands"), isOn: $store.settings.analytics.shareQuota).disabled(!store.settings.analytics.enabled)
                Text(L10n.t("Off by default. Sends country, platform, agent, reminder-stage count and a daily activity band. Quota bands require separate consent. No account ID, exact usage, reset time, prompts, tokens or cookies. Cloudflare processes your IP to determine country but this app does not store it in analytics.")).font(.caption).foregroundStyle(.secondary)
                Button(L10n.t("Delete shared reports and turn off")) { Task { await store.deleteAnalytics() } }.disabled(store.isMock)
                Link(L10n.t("Analytics privacy details"), destination: URL(string: "https://joe05520.github.io/usage-sentinel/insights.html")!)
                Text(store.analyticsStatus).font(.caption).textSelection(.enabled)
            }
            Section(L10n.t("Privacy & Diagnostics")) {
                Text(L10n.t("Account history stays local by default. Optional analytics sends only the daily fields shown above. Official Codex handles its own authentication.")).font(.caption)
                HStack { Button(L10n.t("Diagnostics…")) { store.openWindow?("diagnostics") }; Button(L10n.t("Event History…")) { store.openWindow?("history") } }
            }
            if store.isMock {
                Section(L10n.t("Mock scenarios · no live account reads")) {
                    Button(L10n.t("Test Quota Reminders: 30 → 20 → 5 → reset")) { Task { await store.runReminderSelfTest() } }
                    ForEach(1...5, id: \.self) { scenario in Button(L10n.f("Run Scenario %d", scenario)) { store.runScenario(scenario) } }
                }
            } else {
                Section(L10n.t("Testing")) {
                    Button(L10n.t("Open Isolated Mock App")) {
                        let config = NSWorkspace.OpenConfiguration(); config.arguments = ["--mock", "--show-settings"]; config.createsNewApplicationInstance = true
                        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config)
                    }
                }
            }
            if let error = store.errorMessage { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
        }
        // Recreate picker option labels when the app language changes; ForEach identities otherwise cache them.
        .id(store.settings.language)
        .formStyle(.grouped).frame(width: 590, height: 740)
        .onChange(of: store.settings) { _, _ in store.saveSettings() }
        .sheet(isPresented: $showManual) { ManualUsageView().environmentObject(store) }
    }
    private func intervalPicker(_ title: String, selection: Binding<Double>) -> some View {
        Picker(L10n.t(title), selection: selection) { ForEach([2,5,10,15,30], id: \.self) { value in Text(L10n.f("%d min", value)).tag(Double(value*60)) } }
    }
}
struct ManualUsageView: View {
    @EnvironmentObject var store: SentinelStore
    @Environment(\.dismiss) var dismiss
    @State private var remaining = 50.0
    @State private var reset = Date().addingTimeInterval(3*86400)
    @State private var duration = 10080
    @State private var name = "Weekly"
    @State private var product = "Codex"
    @State private var knowsReset = true
    var body: some View {
        Form {
            Text(L10n.t("Manual Snapshot")).font(.title2)
            Text(L10n.t("User entered evidence is labeled Manual. Save another snapshot to detect changes. Switch to CLI for automatic monitoring.")).font(.caption)
            Picker(L10n.t("AI agent"), selection: $product) {
                ForEach(["Codex", "Claude", "Gemini", "Grok", "Custom"], id: \.self) { Text($0).tag($0) }
            }
            TextField(L10n.t("Product"), text: $product); TextField(L10n.t("Bucket name"), text: $name)
            Picker(L10n.t("Window"), selection: $duration) { Text(L10n.t("5-hour")).tag(300); Text(L10n.t("Weekly")).tag(10080) }
            Slider(value: $remaining, in: 0...100, step: 1) { Text(L10n.t("Remaining")) }
            Text(L10n.f("%d%% remaining", Int(remaining)))
            Toggle(L10n.t("Reset time known"), isOn: $knowsReset)
            if knowsReset { DatePicker(L10n.t("Next regular reset"), selection: $reset) }
            HStack {
                Button(L10n.t("Cancel")) { dismiss() }
                Button(L10n.t("Save Snapshot")) {
                    let now = Date()
                    let bucket = UsageBucket(id: "manual.\(product.lowercased()).\(duration)", name: name, product: product, remainingPercent: remaining, usedPercent: 100-remaining, resetAt: knowsReset ? reset : nil, windowDuration: Double(duration*60), source: "Manual · user entered", lastUpdated: now)
                    Task { await store.saveManual(UsageState(timestamp: now, buckets: [bucket], source: "Manual · user entered", accountFingerprint: "manual", plan: nil, resetCredits: nil, ordinaryUsageAllowed: nil)); dismiss() }
                }.buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width: 440)
    }
}
