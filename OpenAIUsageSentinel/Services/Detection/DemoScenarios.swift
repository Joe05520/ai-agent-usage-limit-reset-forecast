import Foundation

public enum DemoScenarios {
    public static func usage(_ remaining: Double, at: Date, resetAt: Date) -> UsageState {
        UsageState(timestamp: at, buckets: [UsageBucket(id: "codex.secondary", name: "Weekly", product: "Codex", remainingPercent: remaining, usedPercent: 100-remaining, resetAt: resetAt, windowDuration: 7*86400, source: "Mock · scenario", lastUpdated: at)], source: "Mock · scenario", accountFingerprint: "mock-account", plan: "plus", resetCredits: 2, ordinaryUsageAllowed: true)
    }
    public static func reports(_ count: Int, platform: String, now: Date, official: Bool = false) -> [ResetSignal] {
        (0..<count).map { index in
            let source = SignalSource(title: official ? "Codex global reset announcement" : "My Codex weekly quota just reset · \(platform) account \(index)", url: URL(string: official ? "https://help.openai.com/en/articles/11369540-using-codex-with-your-chatgpt-plan#mock-announcement" : "https://example.com/mock/\(platform.lowercased())/\(index)")!, platform: official ? "OpenAI Help Center" : platform, publishedAt: now.addingTimeInterval(Double(-index*120)), fetchedAt: now, author: official ? "OpenAI (MOCK)" : "mock-\(platform)-user-\(index)", snippet: official ? "MOCK: Today we reset eligible Codex usage limits. This is a test fixture, not a real announcement." : "MOCK \(platform) report \(index): My weekly allowance returned to 100% unexpectedly. Anyone else?", official: official)
            return ResetSignal(source: source, product: "Codex", model: nil, plan: "plus", behavior: official ? .automaticGlobal : .suspectedGlobal, isFirsthand: true)
        }
    }
    public static func run(_ scenario: Int, now: Date = Date()) -> [ResetEvent] {
        let future = now.addingTimeInterval(3*86400)
        let before = usage(20, at: now.addingTimeInterval(-300), resetAt: scenario == 1 ? now.addingTimeInterval(-60) : future)
        let after = usage(100, at: now, resetAt: now.addingTimeInterval(7*86400))
        switch scenario {
        case 1, 2: return PersonalResetDetector.detect(before: before, after: after)
        case 3: return EventEngine.merge(signals: reports(2, platform: "Reddit", now: now), personal: [], into: [], now: now)
        case 4: return EventEngine.merge(signals: reports(8, platform: "Reddit", now: now) + reports(3, platform: "GitHub", now: now), personal: PersonalResetDetector.detect(before: before, after: after), into: [], now: now)
        case 5: return EventEngine.merge(signals: reports(1, platform: "OpenAI Help Center", now: now, official: true), personal: [], into: [], now: now)
        default: return []
        }
    }
}
