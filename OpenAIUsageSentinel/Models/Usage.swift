import Foundation

public struct UsageBucket: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var product: String
    public var remainingPercent: Double
    public var usedPercent: Double
    public var resetAt: Date?
    public var windowDuration: TimeInterval?
    public var source: String
    public var lastUpdated: Date
    public var shortLabel: String {
        if windowDuration == 300 * 60 { return "5h" }
        if windowDuration == 10080 * 60 { return "W" }
        return name
    }
}

public struct UsageState: Codable, Equatable, Sendable {
    public var timestamp: Date
    public var buckets: [UsageBucket]
    public var source: String
    public var accountFingerprint: String?
    public var plan: String?
    public var resetCredits: Int?
    public var ordinaryUsageAllowed: Bool?
}
public typealias UsageSnapshot = UsageState

public enum SentinelError: LocalizedError {
    case unavailable(String)
    public var errorDescription: String? {
        switch self { case .unavailable(let message): return message }
    }
}
