import Foundation

public enum MenuBarStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case standard, compact, percentages, singleQuota, icon
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .standard: return L10n.t("Standard")
        case .compact: return L10n.t("Compact")
        case .percentages: return L10n.t("Percentages only")
        case .singleQuota: return L10n.t("Single quota")
        case .icon: return L10n.t("Icon only")
        }
    }
    public var explanation: String {
        switch self {
        case .standard: return L10n.t("Quota labels and percentages with the status icon.")
        case .compact: return L10n.t("Short labels with tight spacing to save menu bar width.")
        case .percentages: return L10n.t("Percentages in the order shown below; hover for quota names.")
        case .singleQuota: return L10n.t("Show just the quota you choose. If it disappears, use the first available quota.")
        case .icon: return L10n.t("Keep only the status icon; open the popover for usage details.")
        }
    }
}

public struct MenuBarAppearance: Codable, Equatable, Sendable {
    public var style: MenuBarStyle = .standard
    public var showSignalCount = false
    public var showBankedCredits = true
    public var selectedBucketID: String?
    public init() {}
}

public enum MenuBarDisplay {
    public static func buckets(_ usage: UsageState, settings: AppSettings) -> [UsageBucket] {
        let sorted = usage.buckets.sorted {
            let lhs = $0.windowDuration ?? .greatestFiniteMagnitude
            let rhs = $1.windowDuration ?? .greatestFiniteMagnitude
            return lhs == rhs ? $0.id < $1.id : lhs < rhs
        }
        if settings.appearance.style == .singleQuota {
            if let selected = sorted.first(where: { $0.id == settings.appearance.selectedBucketID }) { return [selected] }
            return (sorted.first(where: { $0.product == "Codex" }) ?? sorted.first).map { [$0] } ?? []
        }
        if settings.appearance.style == .icon {
            let codex = sorted.filter { $0.product == "Codex" }
            return Array((codex.isEmpty ? sorted : codex).prefix(3))
        }
        let visible = sorted.filter { $0.windowDuration == 7*86400 ? settings.showWeekly : settings.showShort }
        let codex = visible.filter { $0.product == "Codex" }
        return Array((codex.isEmpty ? visible : codex).prefix(3))
    }
    public static func title(usage: UsageState?, available: Bool, signalCount: Int, settings: AppSettings, mock: Bool = false) -> String {
        let prefix = mock ? "[MOCK] " : ""
        let suffix = settings.appearance.showSignalCount && signalCount > 0 ? " · ⚡\(signalCount)" : ""
        guard available, let usage, !usage.buckets.isEmpty else { return prefix + L10n.t("◉ Usage ?", language: settings.language) + suffix }
        let values = buckets(usage, settings: settings)
        func percent(_ bucket: UsageBucket) -> String { "\(Int(bucket.remainingPercent))%" }
        let text: String
        switch settings.appearance.style {
        case .standard:
            text = "◉ " + (values.isEmpty ? L10n.t("Usage", language: settings.language) : values.map { "\($0.shortLabel) \(percent($0))" }.joined(separator: " · "))
        case .compact:
            text = values.isEmpty ? "◉" : values.map { "\($0.shortLabel)\(percent($0))" }.joined(separator: " · ")
        case .percentages:
            text = values.isEmpty ? "◉" : values.map(percent).joined(separator: " / ")
        case .singleQuota:
            text = values.first.map { "\($0.shortLabel) \(percent($0))" } ?? "◉"
        case .icon: text = "◉"
        }
        return prefix + text + suffix
    }
    public static func tooltip(usage: UsageState?, available: Bool, signalCount: Int, settings: AppSettings, mock: Bool = false) -> String {
        guard available, let usage else { return "Usage Sentinel\(mock ? " · MOCK" : "") · " + L10n.t("Usage unavailable", language: settings.language) }
        let values = buckets(usage, settings: settings)
        let summary = values.map { L10n.f("%@ %@: %d%% remaining", $0.product, L10n.t($0.name, language: settings.language), Int($0.remainingPercent), language: settings.language) }.joined(separator: " · ")
        return "Usage Sentinel\(mock ? " · MOCK" : "")" + (summary.isEmpty ? "" : "\n" + summary) + (settings.appearance.showSignalCount && signalCount > 0 ? "\n" + L10n.f("%d active reset signals", signalCount, language: settings.language) : "")
    }
    // Settings-only illustration. It is never assigned to live usage or persisted as a snapshot.
    public static var previewUsage: UsageState {
        let now = Date()
        return UsageState(timestamp: now, buckets: [
            UsageBucket(id: "preview.short", name: "5-hour", product: "Codex", remainingPercent: 72, usedPercent: 28, resetAt: nil, windowDuration: 18000, source: "Illustrative preview", lastUpdated: now),
            UsageBucket(id: "preview.weekly", name: "Weekly", product: "Codex", remainingPercent: 61, usedPercent: 39, resetAt: nil, windowDuration: 604800, source: "Illustrative preview", lastUpdated: now)
        ], source: "Illustrative preview", accountFingerprint: nil, plan: nil, resetCredits: nil, ordinaryUsageAllowed: nil)
    }
}
