import Foundation
import AppKit
import Combine
import ServiceManagement

@MainActor
final class SentinelStore: ObservableObject {
    @Published var settings = AppSettings() { didSet { L10n.language = settings.language } }
    @Published var usage: UsageState?
    @Published var usageAvailable = false
    @Published var watchSignals: [ResetSignal] = []
    @Published var events: [ResetEvent] = []
    @Published var history: [UsageSnapshot] = []
    @Published var diagnostics: [SourceDiagnostic] = []
    @Published var errorMessage: String?
    @Published var updateStatus = ""
    @Published var updateManifest: UpdateManifest?
    @Published var updateBusy = false
    @Published var analyticsStatus = ""
    private var lastUpdateCheck = Date.distantPast
    private var analyticsState = AnalyticsState()
    private var analyticsBusy = false
    @Published var usageBusy = false
    @Published var newsBusy = false
    @Published var permission = "Checking…"
    @Published var selectedEventID: UUID?
    @Published var externalMockEvent: ResetEvent?
    @Published var lastSignalRefresh: Date?
    let isMock: Bool
    let notifications = NotificationService()
    private var database: LocalDatabase?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var lastUsageAttempt = Date.distantPast
    private var lastNewsAttempt = Date.distantPast
    private var intent: ResetIntent?
    private var reminderEngine = UsageReminderEngine()
    private var deliveringNotifications = false
    private var deliveryRequested = false
    var openWindow: ((String) -> Void)?
    var activeEvents: [ResetEvent] { events.filter(\.isActive) }
    var menuTitle: String {
        MenuBarDisplay.title(usage: usage, available: usageAvailable, signalCount: activeEvents.count, settings: settings, mock: isMock)
    }
    var menuTooltip: String {
        MenuBarDisplay.tooltip(usage: usage, available: usageAvailable, signalCount: activeEvents.count, settings: settings, mock: isMock)
    }
    init(mock: Bool = ProcessInfo.processInfo.arguments.contains("--mock")) {
        let environment = ProcessInfo.processInfo.environment
        let testing = environment["SENTINEL_TEST_HOST"] == "1" || environment["XCTestConfigurationFilePath"] != nil || NSClassFromString("XCTestCase") != nil
        isMock = mock || testing
        // Hosted tests never load user preferences, touch persistent state, start timers or read accounts.
        if testing { L10n.language = .english; return }
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("OpenAIUsageSentinel")
        do {
            database = try LocalDatabase(url: root.appendingPathComponent(isMock ? "mock.sqlite" : "sentinel.sqlite"))
            if let saved = try database?.load(AppSettings.self, key: "settings") { settings = saved }
            watchSignals = try database?.load([ResetSignal].self, key: "resetWatch") ?? []
            events = try database?.load([ResetEvent].self, key: "events") ?? []
            // Reclassify stored public evidence after classifier improvements; keep its history.
            for index in events.indices where !events[index].ownAccountReset {
                if let source = events[index].sources.first, let signal = SignalClassifier.classify(source) { events[index].type = signal.behavior }
            }
            analyticsState = try database?.load(AnalyticsState.self, key: "analyticsState") ?? AnalyticsState()
            history = try database?.snapshots() ?? []
            usage = history.last
            intent = try database?.load(ResetIntent.self, key: "intent")
            reminderEngine = try database?.load(UsageReminderEngine.self, key: "usageReminderEngine") ?? UsageReminderEngine()
        } catch { errorMessage = "Persistence: \(error.localizedDescription). Original database retained." }
        L10n.language = settings.language
        notifications.onOpen = { [weak self] id in
            guard let self else { return }
            self.externalMockEvent = nil
            if let id, !self.events.contains(where: { $0.id == id }),
               let mockDB = try? LocalDatabase(url: root.appendingPathComponent("mock.sqlite")),
               let mockEvents = try? mockDB.load([ResetEvent].self, key: "events") {
                self.externalMockEvent = mockEvents.first { $0.id == id }
            }
            self.selectedEventID = id; self.openWindow?("history")
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in guard let self else { return }; Task { @MainActor in await self.refreshAll() } })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in guard let self else { return }; Task { @MainActor in await self.refreshUsage() } })
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in guard let self else { return }; Task { @MainActor in await self.tick() } }
        timer?.tolerance = 5
        if ProcessInfo.processInfo.environment["SENTINEL_TEST_HOST"] == "1" { return }
        Task {
            permission = await notifications.authorization()
            if permission == "Not requested" { _ = await notifications.requestPermission(); permission = await notifications.authorization() }
            if isMock && ProcessInfo.processInfo.arguments.contains("--reminder-self-test") {
                await runReminderSelfTest()
            } else if isMock && ProcessInfo.processInfo.arguments.contains("--self-test") {
                await runNativeMockSelfTest()
            } else if isMock {
                runScenario(3)
                await deliverNotifications()
            } else { await refreshAll() }
        }
    }
    func setReliableAlerts(_ enabled: Bool) {
        settings.reliableAlerts = enabled; saveSettings()
        if enabled { Task { _ = await notifications.requestPermission(); permission = await notifications.authorization(); await deliverNotifications() } }
    }
    func saveSettings() { persist(settings, key: "settings") }
    private func persist<T: Encodable>(_ value: T, key: String) {
        do { try database?.save(value, key: key) } catch { errorMessage = error.localizedDescription }
    }
    private func saveEvents() {
        events = events.filter { $0.detectedAt > Date().addingTimeInterval(-365*86400) }
        persist(events, key: "events")
    }
    private func tick() async {
        guard !isMock else { return }
        if settings.automaticUpdateChecks != false && Date().timeIntervalSince(lastUpdateCheck) >= 86400 { await checkUpdates() }
        await reportAnalytics()
        if Date().timeIntervalSince(lastUsageAttempt) >= settings.usageInterval { await refreshUsage() }
        if Date().timeIntervalSince(lastNewsAttempt) >= settings.signalInterval { await refreshNews() }
    }
    func checkUpdates() async {
        guard !isMock, !updateBusy else { return }
        updateBusy = true; lastUpdateCheck = Date(); defer { updateBusy = false }
        do {
            updateManifest = try await UpdateService.check(preview: settings.includePreviewUpdates != false)
            let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.5.0"
            updateStatus = updateManifest.map { $0.isNewer(than: current) ? L10n.t("Update available") + ": " + $0.version : L10n.t("You are up to date") } ?? L10n.t("No release in this channel")
            if updateManifest?.isNewer(than: current) != true { updateManifest = nil }
        } catch { updateManifest = nil; updateStatus = error.localizedDescription }
    }
    func downloadUpdate() async {
        guard let manifest = updateManifest, !updateBusy else { return }
        updateBusy = true; defer { updateBusy = false }
        do {
            let file = try await UpdateService.download(manifest, directory: FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0])
            updateStatus = L10n.t("Verified download ready · quit the app, replace it and reopen")
            NSWorkspace.shared.activateFileViewerSelecting([file])
        } catch { updateStatus = error.localizedDescription }
    }
    func reportAnalytics() async {
        guard !isMock, settings.analytics.enabled, let endpoint = ServiceConfiguration.bundled.telemetryURL, !analyticsBusy,
              Date().timeIntervalSince(analyticsState.lastAttempt ?? .distantPast) >= 3600,
              analyticsState.closedDay != nil else { return }
        analyticsBusy = true; defer { analyticsBusy = false }
        do {
            let client = try AnalyticsService.identity()
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.5.0"
            guard let body = AnalyticsState.payload(client: client, preferences: settings.analytics, state: analyticsState, usage: usage, agent: settings.selectedAgent, reminders: settings.reminders.stages.count, now: Date(), version: version) else { return }
            analyticsState.lastAttempt = Date(); persist(analyticsState, key: "analyticsState")
            try await AnalyticsService.send(body, endpoint: endpoint)
            analyticsState.sentDay = body["day"] as? String; persist(analyticsState, key: "analyticsState"); analyticsStatus = L10n.t("Anonymous daily summary sent")
        } catch { analyticsStatus = error.localizedDescription }
    }
    func deleteAnalytics() async {
        settings.analytics.enabled = false; settings.analytics.shareQuota = false; saveSettings()
        guard let endpoint = ServiceConfiguration.bundled.telemetryURL else { return }
        do { try await AnalyticsService.delete(endpoint: endpoint); analyticsState = AnalyticsState(); persist(analyticsState, key: "analyticsState"); analyticsStatus = L10n.t("Shared reports deleted; analytics disabled") }
        catch { analyticsStatus = error.localizedDescription }
    }
    func refreshAll(force: Bool = true) async {
        if isMock { await deliverNotifications(); return }
        async let account: Void = refreshUsage(force: force)
        async let news: Void = refreshNews(force: force)
        _ = await (account, news)
    }
    func refreshUsage(force: Bool = false) async {
        guard !isMock, !usageBusy, force || Date().timeIntervalSince(lastUsageAttempt) >= 15 else { return }
        usageBusy = true; lastUsageAttempt = Date(); let started = Date()
        defer { usageBusy = false }
        do {
            let next: UsageState
            if settings.manualMode {
                next = try await ManualUsageProvider(state: database?.load(UsageState.self, key: "manual")).fetchUsage()
            } else if settings.selectedAgent == .codex { next = try await CodexCLIUsageProvider(customPath: settings.cliPath).fetchUsage() }
            else { next = try await LocalJSONUsageProvider(agent: settings.selectedAgent, path: settings.selectedExportPath).fetchUsage() }
            if usage?.timestamp != next.timestamp { try ingest(next) }
            usageAvailable = Date().timeIntervalSince(next.timestamp) <= 600
            recordDiagnostic("Usage", status: !usageAvailable ? "Export is stale · refresh at source" : settings.manualMode ? "Manual snapshot · not live" : settings.selectedAgent == .codex ? "OK · Codex app-server" : "OK · local export", started: started, success: true)
            await deliverNotifications()
        } catch {
            usageAvailable = false
            recordDiagnostic("Usage", status: error.localizedDescription, started: started, success: false)
        }
    }
    private func ingest(_ next: UsageState) throws {
        let previous = history.last { $0.source == next.source && $0.accountFingerprint == next.accountFingerprint && $0.plan == next.plan }
        let personal = previous.map { PersonalResetDetector.detect(before: $0, after: next, intent: intent) } ?? []
        // Commit snapshot first: disk failures are visible and never silently reported as saved.
        try database?.append(next)
        if settings.analytics.enabled && abs(Date().timeIntervalSince(next.timestamp)) <= 600 {
            let decreased = previous.map { prior in
                next.timestamp > prior.timestamp && next.timestamp.timeIntervalSince(prior.timestamp) <= 900 && next.buckets.contains { bucket in
                    prior.buckets.contains { $0.id == bucket.id && $0.resetAt == bucket.resetAt && $0.remainingPercent > bucket.remainingPercent }
                }
            } ?? false
            analyticsState.observe(next.timestamp, agent: settings.selectedAgent, band: settings.analytics.shareQuota ? AnalyticsState.band(next.buckets.map(\.remainingPercent).min()) : "unknown", consumptionObserved: decreased)
            persist(analyticsState, key: "analyticsState")
        }
        reminderEngine.observe(next)
        persist(reminderEngine, key: "usageReminderEngine")
        usage = next; history.append(next); history = history.filter { $0.timestamp > Date().addingTimeInterval(-35*86400) }
        events = EventEngine.merge(signals: [], personal: personal, into: events, now: next.timestamp)
        saveEvents()
    }
    func refreshNews(force: Bool = false) async {
        guard !isMock, !newsBusy, force || Date().timeIntervalSince(lastNewsAttempt) >= 15 else { return }
        newsBusy = true; lastNewsAttempt = Date(); defer { newsBusy = false }
        let sources = SourceCatalog.enabled(settings)
        await withTaskGroup(of: (String, Date, [ResetSignal]?, String?).self) { group in
            for source in sources {
                group.addTask {
                    let start = Date()
                    do { return (source.name, start, try await source.fetchSignals(), nil) }
                    catch { return (source.name, start, nil, error.localizedDescription) }
                }
            }
            var signals: [ResetSignal] = []
            for await (name, start, result, error) in group {
                signals += result ?? []
                if let result, name.hasPrefix("Codex Resets") || name.hasPrefix("Tibo radar") {
                    let host = name.hasPrefix("Codex Resets") ? "codex-resets.com" : "codex-reset.com"
                    watchSignals.removeAll { $0.source.viaURL?.host == host }
                    watchSignals += result
                    persist(watchSignals, key: "resetWatch")
                }
                recordDiagnostic(name, status: error ?? "OK · \(result?.count ?? 0) matching reports", started: start, success: error == nil)
            }
            events = EventEngine.merge(signals: signals, personal: [], into: events, now: Date())
            lastSignalRefresh = Date(); saveEvents()
        }
        await deliverNotifications()
    }
    private func recordDiagnostic(_ name: String, status: String, started: Date, success: Bool) {
        let previous = diagnostics.first { $0.name == name }
        diagnostics.removeAll { $0.name == name }
        diagnostics.append(SourceDiagnostic(name: name, status: status, checkedAt: Date(), lastSuccess: success ? Date() : previous?.lastSuccess, latencyMS: Int(Date().timeIntervalSince(started)*1000), nextRetry: nil))
        diagnostics.sort { $0.name < $1.name }
        persist(diagnostics, key: "diagnostics")
    }
    func deliverNotifications() async {
        if deliveringNotifications { deliveryRequested = true; return }
        deliveringNotifications = true
        defer {
            deliveringNotifications = false
            if deliveryRequested { deliveryRequested = false; Task { await deliverNotifications() } }
        }
        for event in events where NotificationPolicy.shouldNotify(event, settings: settings, now: Date()) {
            do {
                if try await notifications.send(event, mock: isMock), let index = events.firstIndex(where: { $0.id == event.id }) {
                    if settings.reliableAlerts && event.confidence >= 0.5 { events[index].notifiedReliable = true }
                    events[index].notifiedRank = max(events[index].notifiedRank, event.level.rank)
                    events[index].notifiedOwnReset = events[index].notifiedOwnReset || event.ownAccountReset
                    saveEvents()
                }
            } catch { errorMessage = "Notification: \(error.localizedDescription)" }
        }
        if usageAvailable, let current = usage {
            for reminder in reminderEngine.pending(current, settings: settings.reminders, now: Date()) {
                do {
                    if try await notifications.sendReminder(reminder, mock: isMock) {
                        reminderEngine.markDelivered(reminder)
                        persist(reminderEngine, key: "usageReminderEngine")
                    }
                } catch { errorMessage = "Usage reminder: \(error.localizedDescription)" }
            }
        }
        permission = await notifications.authorization()
        persist(permission, key: "notificationPermission")
        persist(await notifications.deliverySummary(), key: "notificationDelivery")
        persist(SMAppService.mainApp.status == .enabled, key: "launchAtLoginEnabled")
    }
    private func runNativeMockSelfTest() async {
        var allEvents: [ResetEvent] = []
        var results: [[String: String]] = []
        for scenario in 1...5 {
            events = DemoScenarios.run(scenario)
            usage = DemoScenarios.usage(scenario == 3 ? 37 : 100, at: Date(), resetAt: Date().addingTimeInterval(3*86400)); usageAvailable = true
            saveEvents()
            await deliverNotifications()
            if let event = events.first { results.append(["scenario": String(scenario), "type": event.type.rawValue, "confidence": String(event.confidence), "level": event.level.rawValue, "notificationSubmitted": String(event.notifiedRank >= 0), "eventID": event.id.uuidString]) }
            allEvents += events
        }
        events = allEvents; saveEvents()
        persist(results, key: "mockSelfTest")
        persist(await notifications.deliverySummary(), key: "notificationDelivery")
    }
    func snoozeReminders() {
        settings.reminders.snoozedUntil = Date().addingTimeInterval(3600); saveSettings()
    }
    func resumeReminders() {
        settings.reminders.snoozedUntil = nil; saveSettings()
        Task { await deliverNotifications() }
    }
    func runReminderSelfTest() async {
        guard isMock else { return }
        reminderEngine = UsageReminderEngine(); settings.reminders = UsageReminderSettings()
        events = []
        let start = Date(); let reset = start.addingTimeInterval(3*86400)
        var results: [[String: String]] = []
        for (index, remaining) in [30.0, 20, 19, 5, 4, 100, 20].enumerated() {
            let snapshot = DemoScenarios.usage(remaining, at: start.addingTimeInterval(Double(index)), resetAt: reset)
            usage = snapshot; usageAvailable = true; reminderEngine.observe(snapshot)
            let candidates = reminderEngine.pending(snapshot, settings: settings.reminders, now: Date())
            await deliverNotifications()
            results.append(["remaining": String(remaining), "candidates": String(candidates.count), "submitted": String(reminderEngine.pending(snapshot, settings: settings.reminders, now: Date()).isEmpty && !candidates.isEmpty)])
        }
        persist(results, key: "reminderSelfTest")
        persist(await notifications.deliverySummary(), key: "notificationDelivery")
    }
    func recordIntent(_ type: ResetEventType) { intent = ResetIntent(type: type, recordedAt: Date()); persist(intent, key: "intent") }
    func saveManual(_ state: UsageState) async {
        persist(state, key: "manual"); settings.manualMode = true; saveSettings(); await refreshUsage(force: true)
    }
    func runScenario(_ scenario: Int) {
        guard isMock else { return }
        events = DemoScenarios.run(scenario)
        usage = DemoScenarios.usage(scenario == 3 ? 37 : 100, at: Date(), resetAt: Date().addingTimeInterval(3*86400)); usageAvailable = true
        diagnostics = [SourceDiagnostic(name: "Mock", status: "Scenario \(scenario) · no network/account reads", checkedAt: Date(), lastSuccess: Date(), latencyMS: 0, nextRetry: nil)]
        saveEvents(); Task { await deliverNotifications() }
    }
    var diagnosticsText: String {
        (["AI Usage Sentinel 1.4", "Mode: \(isMock ? "MOCK" : settings.manualMode ? "Manual" : "Live Codex")", "Notifications: \(permission)", "Quota reminders: \(settings.reminders.enabled ? "enabled" : "disabled") · thresholds \(settings.reminders.thresholds.map { String(Int($0)) }.joined(separator: ", "))% · snooze \(settings.reminders.snoozedUntil?.formatted() ?? "none")", "CLI: \(CodexCLIUsageProvider.executable(customPath: settings.cliPath) ?? "not found")", "Persistence: \(database?.url.path ?? "unavailable")"] + diagnostics.map { "\($0.name): \($0.status) · \($0.latencyMS ?? 0) ms · \($0.checkedAt?.formatted() ?? "never")" } + (usage?.buckets.map { "\($0.product) \($0.name): \(Int($0.remainingPercent))% left · reset \($0.resetAt?.formatted() ?? "unknown")" } ?? [])).joined(separator: "\n")
    }
}
