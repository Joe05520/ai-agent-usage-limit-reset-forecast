import XCTest
#if SWIFT_PACKAGE
@testable import SentinelCore
#else
@testable import OpenAIUsageSentinel
#endif
final class AgentUsageTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1791100800)
    func json(_ changes: [String: Any] = [:]) throws -> Data {
        var root: [String: Any] = ["schemaVersion": 1, "timestamp": "2026-10-04T08:00:00Z", "profile": "local-label", "buckets": [["id": "weekly", "name": "Weekly", "remainingPercent": 23, "windowDurationMins": 10080, "resetAt": "2026-10-07T08:00:00Z"]]]
        changes.forEach { root[$0] = $1 }; return try JSONSerialization.data(withJSONObject: root)
    }
    func testGeminiAndGrokKeepSeparateIDsAndSources() throws {
        let gemini = try LocalJSONUsageProvider.parse(json(), agent: .gemini, now: now)
        let grok = try LocalJSONUsageProvider.parse(json(), agent: .grok, now: now)
        XCTAssertNotEqual(gemini.buckets[0].id, grok.buckets[0].id)
        XCTAssertEqual(gemini.buckets[0].product, "Gemini"); XCTAssertTrue(grok.source.contains("user-provided"))
        XCTAssertNotEqual(gemini.accountFingerprint, "local-label")
        XCTAssertEqual(gemini.timestamp, now)
    }
    func testInvalidMissingBooleanDuplicateAndFutureExportsRejected() throws {
        for changes: [String: Any] in [["schemaVersion": 2], ["timestamp": "2099-01-01T00:00:00Z"], ["buckets": []], ["buckets": [["id":"x","name":"Weekly","remainingPercent":true]]], ["buckets": [["id":"x","name":"Weekly","remainingPercent":101]]]] {
            XCTAssertThrowsError(try LocalJSONUsageProvider.parse(json(changes), agent: .claude, now: now))
        }
    }
    func testLocalAgentResetUsesVendorSourceNotOpenAI() throws {
        var before = try LocalJSONUsageProvider.parse(json(), agent: .claude, now: now)
        var after = before; after.timestamp = now.addingTimeInterval(60); after.buckets[0].remainingPercent = 100
        let event = PersonalResetDetector.detect(before: before, after: after)[0]
        XCTAssertEqual(event.product, "Claude"); XCTAssertEqual(event.sources[0].url.host, "code.claude.com"); XCTAssertEqual(event.reportCount, 0)
        before.source = "Local Claude · user-provided export"; after.source = before.source
        XCTAssertEqual(PersonalResetDetector.detect(before: before, after: after)[0].confidence, 0.3)
    }
    func testOldSettingsDefaultToCodexAndPathsAreIndependent() throws {
        var settings = AppSettings(); settings.reminders.warningPercent = 30
        settings.selectedAgent = .gemini; settings.selectedExportPath = "/tmp/gemini.json"; settings.selectedAgent = .grok
        XCTAssertEqual(settings.selectedExportPath, ""); settings.selectedAgent = .gemini; XCTAssertEqual(settings.selectedExportPath, "/tmp/gemini.json")
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as! [String: Any]
        json.removeValue(forKey: "agentSelection"); json.removeValue(forKey: "agentExportPaths")
        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(restored.selectedAgent, .codex); XCTAssertEqual(restored.reminders.stages, [30,5])
    }
}
