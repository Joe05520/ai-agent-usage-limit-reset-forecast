import XCTest
import CryptoKit
#if SWIFT_PACKAGE
@testable import SentinelCore
#else
@testable import OpenAIUsageSentinel
#endif
final class SecurityAndUpdateTests: XCTestCase {
    func fixture(_ changes: [String: Any] = [:]) throws -> Data {
        let version = "1.5.0"
        let assets = ["macOS", "Windows", "Linux"].map { p in ["platform": p, "url": "https://github.com/Joe05520/usage-sentinel/releases/download/v\(version)/UsageSentinel-\(version)-\(p == "macOS" ? "macOS-universal.zip" : p == "Windows" ? "Windows-x64.zip" : "Linux-x64.tar.gz")", "sha256": String(repeating:"a",count:64), "size":2_000_000] as [String:Any] }
        var value: [String:Any] = ["schema":1,"version":version,"channel":"preview","releaseURL":"https://github.com/Joe05520/usage-sentinel/releases/tag/v\(version)","assets":assets]
        changes.forEach { value[$0] = $1 }; return try JSONSerialization.data(withJSONObject:value)
    }
    func testSignedManifestRejectsTamperingWrongChannelAndForeignAssets() throws {
        let key = Curve25519.Signing.PrivateKey(), publicKey = key.publicKey.rawRepresentation.base64EncodedString()
        let data = try fixture(), signature = Data(try key.signature(for:data).base64EncodedString().utf8)
        let manifest = try UpdateManifest.verified(data:data,signature:signature,publicKey:publicKey,channel:"preview")
        XCTAssertTrue(manifest.isNewer(than:"1.4.9")); XCTAssertFalse(manifest.isNewer(than:"1.5.0")); XCTAssertFalse(manifest.isNewer(than:"2.0.0"))
        XCTAssertThrowsError(try UpdateManifest.verified(data:try fixture(["version":"9.9.9"]),signature:signature,publicKey:publicKey,channel:"preview"))
        XCTAssertThrowsError(try UpdateManifest.verified(data:data,signature:signature,publicKey:publicKey,channel:"stable"))
        let evil = try fixture(["assets":[["platform":"macOS","url":"https://evil.test/app.zip","size":2_000_000,"sha256":String(repeating:"a",count:64)]]])
        XCTAssertThrowsError(try UpdateManifest.verified(data:evil,signature:Data(try key.signature(for:evil).base64EncodedString().utf8),publicKey:publicKey,channel:"preview"))
    }
    func testVersionAndExternalSchemes() {
        for version in ["1", "1.2", "1.2.3.4", "1.2.-3", "one.2.3", "1.2.٣", "1000.1.1"] { XCTAssertNil(UpdateManifest.versionParts(version)) }
        for value in ["file:///etc/passwd", "javascript:alert(1)", "http://example.com", "https://user:secret@example.com", "https://example.com:444"] { XCTAssertFalse(SafeURL.external(URL(string:value)!)) }
        XCTAssertTrue(SafeURL.external(URL(string:"https://example.com/news")!))
    }
    func testAnalyticsDefaultsLocalAndPayloadHasNoAccountInformation() throws {
        let now = Date(), id = UUID().uuidString.lowercased()
        var state = AnalyticsState(); state.closedDay = AnalyticsDay(day: AnalyticsState.dayString(now.addingTimeInterval(-86400)), observations: 2, agent: .codex, quotaBand: "20-49")
        let usage = UsageState(timestamp:now,buckets:[UsageBucket(id:"private-id",name:"Private quota",product:"Private model",remainingPercent:23,usedPercent:77,resetAt:now.addingTimeInterval(86400),windowDuration:3600,source:"private source",lastUpdated:now)],source:"private",accountFingerprint:"PRIVATE_ACCOUNT",plan:"Pro",resetCredits:3,ordinaryUsageAllowed:true)
        var prefs = AnalyticsPreferences()
        XCTAssertNil(AnalyticsState.payload(client:id,preferences:prefs,state:state,usage:usage,agent:.codex,reminders:5,now:now,version:"1.5.0"))
        prefs.enabled = true
        let body = try XCTUnwrap(AnalyticsState.payload(client:id,preferences:prefs,state:state,usage:usage,agent:.codex,reminders:5,now:now,version:"1.5.0"))
        XCTAssertEqual(body["quotaBand"] as? String,"unknown")
        let text = String(decoding:try JSONSerialization.data(withJSONObject:body),as:UTF8.self)
        for forbidden in ["PRIVATE_ACCOUNT", "Private model", "private source", "resetAt", "usedPercent", "Pro"] { XCTAssertFalse(text.contains(forbidden)) }
        prefs.shareQuota = true
        XCTAssertEqual(AnalyticsState.payload(client:id,preferences:prefs,state:state,usage:usage,agent:.codex,reminders:5,now:now,version:"1.5.0")?["quotaBand"] as? String,"20-49")
        state.sentDay = state.closedDay?.day
        XCTAssertNil(AnalyticsState.payload(client:id,preferences:prefs,state:state,usage:usage,agent:.codex,reminders:5,now:now,version:"1.5.0"))
    }
    func testAnalyticsClosesDayCountsOnlyChangesAndPreservesLowestBand() throws {
        let first = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-03T10:00:00Z"))
        var state = AnalyticsState()
        state.observe(first, band: "50-100")
        state.observe(first, band: "0-4", consumptionObserved: true)
        XCTAssertEqual(state.observations, 0)
        state.observe(first.addingTimeInterval(300), band: "20-49", consumptionObserved: true)
        state.observe(first.addingTimeInterval(600), agent: .claude, band: "50-100")
        XCTAssertEqual(state.observations, 1)
        XCTAssertEqual(state.quotaBand, "20-49")
        XCTAssertEqual(state.agent, .custom)
        state.observe(first.addingTimeInterval(86400), band: "50-100")
        XCTAssertEqual(state.closedDay?.day, "2026-10-03")
        XCTAssertEqual(state.closedDay?.observations, 1)
        XCTAssertEqual(state.closedDay?.agent, .custom)
        XCTAssertEqual(state.observations, 0)
        XCTAssertEqual(state.quotaBand, "50-100")
        var prefs = AnalyticsPreferences(); prefs.enabled = true
        XCTAssertNil(AnalyticsState.payload(client: UUID().uuidString, preferences: prefs, state: state, usage: nil, agent: .codex, reminders: 2, now: first.addingTimeInterval(3 * 86400), version: "1.5.0"))
    }

}
