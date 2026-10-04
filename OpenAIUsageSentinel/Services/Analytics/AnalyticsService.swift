import Foundation

public struct AnalyticsPreferences: Codable, Equatable, Sendable {
    public var enabled = false
    public var shareQuota = false
    public init() {}
}
public struct AnalyticsDay: Codable, Sendable {
    public var day: String
    public var observations: Int
    public var agent: AgentKind
    public var quotaBand: String
}
public struct AnalyticsState: Codable, Sendable {
    public var day = ""
    public var observations = 0
    public var lastObservation: Date?
    public var agent: AgentKind?
    public var quotaBand: String?
    public var closedDay: AnalyticsDay?
    public var sentDay: String?
    public var lastAttempt: Date?
    public init() {}
    public mutating func observe(_ timestamp: Date, agent selectedAgent: AgentKind = .codex, band: String = "unknown", consumptionObserved: Bool = false) {
        let date = Self.dayString(timestamp)
        if date != day {
            if lastObservation != nil { closedDay = AnalyticsDay(day: day, observations: observations, agent: agent ?? .custom, quotaBand: quotaBand ?? "unknown") }
            day = date; observations = 0; lastObservation = nil; agent = selectedAgent; quotaBand = band
        }
        guard lastObservation != timestamp else { return }
        if agent != selectedAgent { agent = .custom }
        if consumptionObserved { observations = min(21, observations + 1) }
        let order = ["0-4","5-19","20-49","50-100","unknown"]
        if (order.firstIndex(of: band) ?? 4) < (order.firstIndex(of: quotaBand ?? "unknown") ?? 4) { quotaBand = band }
        lastObservation = timestamp
    }
    public static func dayString(_ date: Date) -> String { String(ISO8601DateFormatter().string(from: date).prefix(10)) }
    public static func band(_ remaining: Double?) -> String {
        guard let remaining, remaining.isFinite else { return "unknown" }
        return remaining < 5 ? "0-4" : remaining < 20 ? "5-19" : remaining < 50 ? "20-49" : "50-100"
    }
    public static func payload(client: String, preferences: AnalyticsPreferences, state: AnalyticsState, usage: UsageState?, agent: AgentKind, reminders: Int, now: Date, version: String) -> [String: Any]? {
        guard preferences.enabled, let closed = state.closedDay, state.sentDay != closed.day,
              [dayString(now), dayString(now.addingTimeInterval(-86400))].contains(closed.day) else { return nil }
        return ["schema":1,"consent":true,"client":client,"kind":"app","day":closed.day,"platform":"macOS","version":version,"agent":closed.agent.rawValue,"quotaBand":preferences.shareQuota ? closed.quotaBand : "unknown","activityBand":closed.observations == 0 ? "0" : closed.observations <= 5 ? "1-5" : closed.observations <= 20 ? "6-20" : "21+","reminders":min(5,max(0,reminders))]
    }
}
public enum AnalyticsService {
    private struct Identity: Codable { var month: String; var current: String; var retained: [String] }
    public static func identity(now: Date = Date()) throws -> String {
        let month = String(AnalyticsState.dayString(now).prefix(7))
        let bytes = try KeychainStore.read(account: "analytics-identity-v1")
        var identity = try bytes.map { try JSONDecoder().decode(Identity.self, from: $0) } ?? Identity(month: month, current: UUID().uuidString.lowercased(), retained: [])
        if identity.month != month { identity.retained = Array((identity.retained + [identity.current]).suffix(2)); identity.current = UUID().uuidString.lowercased(); identity.month = month }
        try KeychainStore.save(JSONEncoder().encode(identity), account: "analytics-identity-v1")
        return identity.current
    }
    public static func send(_ body: [String: Any], endpoint: URL) async throws {
        var request = URLRequest(url: endpoint.appendingPathComponent("v1/report")); request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await SecureTransport.read(request, limit: 2048)
        guard response.statusCode == 202 else { throw SentinelError.unavailable("Analytics service unavailable; no report saved for retry") }
    }
    public static func delete(endpoint: URL) async throws {
        guard let bytes = try KeychainStore.read(account: "analytics-identity-v1") else { return }
        let identity = try JSONDecoder().decode(Identity.self, from: bytes)
        for id in identity.retained + [identity.current] {
            var request = URLRequest(url: endpoint.appendingPathComponent("v1/report")); request.httpMethod = "DELETE"; request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONSerialization.data(withJSONObject:["client":id])
            let (_, response) = try await SecureTransport.read(request, limit: 2048)
            guard response.statusCode == 200 else { throw SentinelError.unavailable("Deletion incomplete; retry later") }
        }
        try KeychainStore.delete(account: "analytics-identity-v1")
    }
}
