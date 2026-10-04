import Foundation

public struct AppSettings: Codable, Equatable, Sendable {
    public var showPercent = true
    public var showWeekly = true
    public var showShort = true
    public var usageInterval = 300.0
    public var signalInterval = 300.0
    public var threshold = 0.25
    public var notifyUnexpected = true
    public var notifyEarly = true
    public var notifyLikely = true
    public var notifyOfficial = true
    public var official = true
    public var github = true
    public var reddit = true
    public var hackerNews = false
    public var cliPath = ""
    public var manualMode = false
    public var agentSelection: AgentKind?
    public var agentExportPaths: [String: String]?
    public var selectedAgent: AgentKind {
        get { agentSelection ?? .codex }
        set { agentSelection = newValue }
    }
    public var selectedExportPath: String {
        get { agentExportPaths?[selectedAgent.rawValue] ?? "" }
        set { var paths = agentExportPaths ?? [:]; paths[selectedAgent.rawValue] = newValue; agentExportPaths = paths }
    }
    // Optional storage keeps settings saved by 1.0 decodable without discarding preferences.
    public var reminderConfiguration: UsageReminderSettings?
    public var reminders: UsageReminderSettings {
        get { reminderConfiguration ?? UsageReminderSettings() }
        set { reminderConfiguration = newValue }
    }
    public var menuBarConfiguration: MenuBarAppearance?
    public var appearance: MenuBarAppearance {
        get {
            if let saved = menuBarConfiguration { return saved }
            var migrated = MenuBarAppearance()
            migrated.style = showPercent ? .standard : .icon
            return migrated
        }
        set { menuBarConfiguration = newValue }
    }
    public var appLanguage: AppLanguage?
    public var language: AppLanguage {
        get { appLanguage ?? .english }
        set { appLanguage = newValue }
    }
    public var analyticsConfiguration: AnalyticsPreferences?
    public var analytics: AnalyticsPreferences {
        get { analyticsConfiguration ?? AnalyticsPreferences() }
        set { analyticsConfiguration = newValue }
    }
    public var automaticUpdateChecks: Bool?
    public var includePreviewUpdates: Bool?
    public init() {}
}
public struct SourceDiagnostic: Identifiable, Codable, Sendable {
    public var id: String { name }
    public var name: String
    public var status: String
    public var checkedAt: Date?
    public var lastSuccess: Date?
    public var latencyMS: Int?
    public var nextRetry: Date?
}
