import Foundation
import CryptoKit

public enum AgentKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case codex, claude, gemini, grok, custom
    public var id: String { rawValue }
    public var label: String {
        switch self { case .codex: return "Codex"; case .claude: return "Claude"; case .gemini: return "Gemini"; case .grok: return "Grok"; case .custom: return L10n.t("Custom agent") }
    }
    public var sourceURL: URL {
        URL(string: self == .claude ? "https://code.claude.com/docs/en/statusline" : self == .gemini ? "https://github.com/google-gemini/gemini-cli/blob/main/docs/reference/commands.md" : self == .grok ? "https://docs.x.ai/developers/rate-limits" : "https://chatgpt.com/codex/settings/usage")!
    }
    public static func forProduct(_ name: String) -> Self {
        allCases.first { $0.rawValue != "custom" && name.lowercased().contains($0.rawValue) } ?? .custom
    }
}

/// Reads only an explicitly selected local export. Never reads vendor authentication files.
/// Dates use ISO 8601 in the interoperable JSON schema (not Swift reference-date encoding).
public struct LocalJSONUsageProvider: UsageProvider {
    public var agent: AgentKind
    public var path: String
    public var name: String { "\(agent.label) · local JSON export" }
    public init(agent: AgentKind, path: String) { self.agent = agent; self.path = path }
    public func fetchUsage() async throws -> UsageState {
        let path = NSString(string: path).expandingTildeInPath
        guard !path.isEmpty else { throw SentinelError.unavailable("Choose a local usage JSON export. No subscription API is assumed for \(agent.label).") }
        let url = URL(fileURLWithPath: path)
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size < 1_000_000 else { throw SentinelError.unavailable("Usage export exceeds 1 MB.") }
        let data = try Data(contentsOf: url)
        return try Self.parse(data, agent: agent, now: Date())
    }
    public static func parse(_ data: Data, agent: AgentKind, now: Date) throws -> UsageState {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], root["schemaVersion"] as? Int == 1,
              let timestampText = root["timestamp"] as? String, let timestamp = date(timestampText),
              timestamp <= now.addingTimeInterval(60), let rows = root["buckets"] as? [[String: Any]] else {
            throw SentinelError.unavailable("Invalid usage export: schemaVersion 1, ISO timestamp and buckets are required.")
        }
        let origin = root["origin"] as? String ?? "user-provided export"
        let source = "Local \(agent.label) · \(origin)"
        var buckets: [UsageBucket] = []
        var seen = Set<String>()
        for row in rows {
            guard let id = row["id"] as? String, !id.isEmpty, seen.insert(id).inserted,
                  let value = row["remainingPercent"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
                  value.doubleValue.isFinite, (0...100).contains(value.doubleValue), let name = row["name"] as? String else {
                throw SentinelError.unavailable("Every exported bucket needs a unique id, name and remainingPercent in 0–100.")
            }
            let reset: Date?
            if let text = row["resetAt"] as? String { guard let parsed = date(text) else { throw SentinelError.unavailable("Invalid resetAt date.") }; reset = parsed } else { reset = nil }
            let duration = (row["windowDurationMins"] as? NSNumber)?.doubleValue
            if let duration, !duration.isFinite || duration <= 0 { throw SentinelError.unavailable("Invalid windowDurationMins.") }
            buckets.append(UsageBucket(id: "\(agent.rawValue).\(id)", name: name, product: agent == .custom ? (root["product"] as? String ?? "Custom") : agent.label,
                remainingPercent: value.doubleValue, usedPercent: 100-value.doubleValue, resetAt: reset, windowDuration: duration.map { $0*60 }, source: source, lastUpdated: timestamp))
        }
        guard !buckets.isEmpty else { throw SentinelError.unavailable("No usable quota windows in export; missing limits are not zero.") }
        let fingerprint = (root["profile"] as? String).map { SignalClassifier.digest($0) }
        return UsageState(timestamp: timestamp, buckets: buckets, source: source, accountFingerprint: fingerprint, plan: root["plan"] as? String, resetCredits: nil, ordinaryUsageAllowed: nil)
    }
    private static func date(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}
