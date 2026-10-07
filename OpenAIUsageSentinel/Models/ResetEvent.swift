import Foundation

public enum ResetEventType: String, Codable, CaseIterable, Sendable {
    case scheduled, banked, purchased, automaticGlobal, suspectedGlobal, accountUnexpected, complimentary, forecast, poll, unknown
    public var label: String { L10n.t(englishLabel) }
    public var englishLabel: String {
        switch self {
        case .scheduled: return "Normal reset"
        case .banked: return "Banked reset"
        case .purchased: return "Purchased reset"
        case .automaticGlobal: return "Automatic / global reset"
        case .suspectedGlobal: return "Possible global reset"
        case .accountUnexpected: return "Unexpected account reset"
        case .complimentary: return "Complimentary reset offer"
        case .forecast: return "Reset forecast / teaser"
        case .poll: return "Reset-related poll"
        case .unknown: return "Unclassified quota increase"
        }
    }
}
public enum ConfidenceLevel: String, Codable, Sendable {
    case rumor = "Rumor", early = "Early Signal", likely = "Likely", confirmed = "Confirmed"
    public static func from(_ score: Double) -> Self {
        score >= 0.9 ? .confirmed : score >= 0.6 ? .likely : score >= 0.3 ? .early : .rumor
    }
    public var label: String { L10n.t(rawValue) }
    public var rank: Int { switch self { case .rumor: return 0; case .early: return 1; case .likely: return 2; case .confirmed: return 3 } }
}
public struct SignalSource: Codable, Identifiable, Equatable, Sendable {
    public var id: String { url.absoluteString }
    public var title: String
    public var url: URL
    public var platform: String
    public var publishedAt: Date?
    public var fetchedAt: Date
    public var author: String?
    public var snippet: String
    public var official: Bool
    // Optional additions preserve old persisted source records.
    public var viaURL: URL? = nil
    public var watchContext: String? = nil
    public var expiresAt: Date? = nil
    public var announcedTarget: Date? = nil
    public var isAccountEvidence: Bool { platform.hasPrefix("Local ") || platform == "Manual" }
    public var screenshotEvidence: Bool = false
    public var modifiedAt: Date? = nil
    public var reportedPlan: String? = nil
    public var reportedModel: String? = nil
}
public struct ResetSignal: Codable, Equatable, Sendable {
    public var source: SignalSource
    public var product: String
    public var model: String?
    public var plan: String?
    public var behavior: ResetEventType
    public var isFirsthand: Bool
}
public struct ConfidencePoint: Codable, Equatable, Sendable {
    public var timestamp: Date
    public var score: Double
}
public struct ResetEvent: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID = UUID()
    public var type: ResetEventType
    public var detectedAt: Date
    public var updatedAt: Date
    public var product: String
    public var model: String?
    public var plans: [String]
    public var affectedBuckets: [String]
    public var beforeValue: [String: Double]
    public var afterValue: [String: Double]
    public var confidence: Double
    public var sources: [SignalSource]
    public var explanation: String
    public var ownAccountReset: Bool
    public var timeline: [ConfidencePoint]
    public var notifiedReliable: Bool? = nil
    public var notifiedRank: Int = -1
    public var notifiedOwnReset: Bool = false
    public var ownEvidenceConfidence: Double? = nil
    public var level: ConfidenceLevel { .from(confidence) }
    public var isMockEvidence: Bool { sources.contains { ($0.url.host == "example.com" && $0.url.path.hasPrefix("/mock/")) || $0.author == "OpenAI (MOCK)" || $0.snippet.contains("Mock · scenario") } }
    public var reportCount: Int { sources.filter { !$0.official && !$0.platform.hasPrefix("Local ") && $0.platform != "Manual" }.count }
    public var isActive: Bool { !([ResetEventType.forecast, .poll].contains(type) && sources.allSatisfy { $0.expiresAt.map { $0 <= Date() } ?? false }) && updatedAt > Date().addingTimeInterval(-86400) && type != .scheduled && type != .banked && type != .purchased }
}
public struct ResetIntent: Codable, Sendable {
    public var type: ResetEventType
    public var recordedAt: Date
}
