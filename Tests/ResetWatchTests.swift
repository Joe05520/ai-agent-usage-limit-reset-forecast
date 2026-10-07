import XCTest
#if SWIFT_PACKAGE
@testable import SentinelCore
#else
@testable import OpenAIUsageSentinel
#endif

final class ResetWatchTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func source(_ text: String, handle: String = "thsottiaux", via: String? = nil) -> SignalSource {
        SignalSource(title: "Codex", url: URL(string: "https://x.com/\(handle)/status/123456789")!, platform: "X", publishedAt: now, fetchedAt: now, author: handle, snippet: text, official: false, viaURL: via.flatMap(URL.init(string:)))
    }
    func testLivePublicResetFeeds() async throws {
        guard ProcessInfo.processInfo.environment["SENTINEL_LIVE_RESET"] == "1" else { throw XCTSkip("Public network smoke is opt-in; no account or credentials accessed.") }
        let a = try await CodexResetsSource().fetchSignals()
        let b = try await TiboRadarSource().fetchSignals()
        XCTAssertTrue((a + b).allSatisfy { $0.source.viaURL != nil && !$0.source.official })
        print("PUBLIC RESET SMOKE: \(a.count) attributed history/watch records; \(b.count) radar records; \(b.filter { $0.behavior == .poll }.count) poll-related posts.")
    }
    func testWeightsArePolicyNotProbability() {
        XCTAssertEqual(EventEngine.score(sources: [source("global reset", handle: "codex_resets")], ownReset: false, now: now), 0.75)
        XCTAssertEqual(ResetWatchPolicy.weight(source("reset has been processed")), 0.85)
        XCTAssertLessThan(EventEngine.score(sources: [source("global reset", handle: "codex_resets")], ownReset: false, now: now.addingTimeInterval(7200)), 0.75)
    }
    func testPollsTeasersAndCompletionStaySeparate() {
        XCTAssertEqual(SignalClassifier.classify(source("Vote: improvements or a reset?"))?.behavior, .poll)
        XCTAssertEqual(SignalClassifier.classify(source("I do like giving resets"))?.behavior, .forecast)
        XCTAssertEqual(SignalClassifier.classify(source("Reset all propagated. Enjoy."))?.behavior, .suspectedGlobal)
        XCTAssertEqual(SignalClassifier.classify(source("Global reset landing tomorrow 10am"))?.behavior, .forecast)
        XCTAssertNil(SignalClassifier.classify(source("I love giving updates")))
        XCTAssertNil(SignalClassifier.classify(source("I can't really give a reset")))
    }
    func testSamePostUpgradesFromVoteToCompleted() {
        let poll = SignalClassifier.classify(source("Vote for a reset"))!
        let events = EventEngine.merge(signals: [poll], personal: [], into: [], now: now)
        let complete = SignalClassifier.classify(source("Reset all propagated"))!
        let updated = EventEngine.merge(signals: [complete], personal: [], into: events, now: now.addingTimeInterval(60))
        XCTAssertEqual(updated.count, 1)
        XCTAssertEqual(updated.first?.type, .suspectedGlobal)
    }
    func testNewerCompletionSupersedesPoll() {
        let poll = SignalClassifier.classify(source("Vote for a reset"))!
        var completeSource = source("Reset all propagated")
        completeSource.url = URL(string: "https://x.com/thsottiaux/status/555")!
        completeSource.publishedAt = now.addingTimeInterval(60)
        let complete = SignalClassifier.classify(completeSource)!
        let updated = EventEngine.merge(signals: [poll,complete], personal: [], into: [], now: now.addingTimeInterval(60))
        XCTAssertEqual(updated.count,1)
        XCTAssertEqual(updated.first?.type,.suspectedGlobal)
    }
    func testSpoofMentionDoesNotInheritWeight() {
        var spoof = source("@codex_resets global reset", handle: "random")
        spoof.author = "codex_resets"
        XCTAssertNil(ResetWatchPolicy.weight(spoof))
        spoof.url = URL(string: "https://x.com.evil.test/codex_resets/status/123")!
        XCTAssertNil(ResetWatchPolicy.weight(spoof))
        XCTAssertNil(ResetWatchPolicy.weight(source("reset", via: "https://evil.test")))
    }
    func testMirrorsDoNotStackOrBecomeOfficial() {
        let a = source("Reset all propagated", via: "https://codex-resets.com")
        let b = source("Reset all propagated", via: "https://codex-reset.com")
        XCTAssertEqual(EventEngine.uniqueSources([a,b]).count, 1)
        XCTAssertEqual(EventEngine.score(sources: [a,b], ownReset: false, now: now), 0.85)
        XCTAssertFalse(SignalClassifier.classify(a)!.source.official)
    }
    func testExpiredPollDoesNotNotifyOrMergeWithCompletedReset() {
        let poll = SignalClassifier.classify(source("Vote for a reset"))!
        var completedSource = source("Reset all propagated")
        completedSource.url = URL(string: "https://x.com/thsottiaux/status/987654321")!
        let complete = SignalClassifier.classify(completedSource)!
        let events = EventEngine.merge(signals: [poll,complete], personal: [], into: [], now: now)
        XCTAssertEqual(events.count, 2)
        let polled = events.first { $0.type == .poll }!
        XCTAssertTrue(NotificationPolicy.shouldNotify(polled, settings: AppSettings(), now: now))
        var disabled = AppSettings(); disabled.watchResets = false
        XCTAssertFalse(NotificationPolicy.shouldNotify(polled, settings: disabled, now: now))
        XCTAssertFalse(NotificationPolicy.shouldNotify(polled, settings: AppSettings(), now: now.addingTimeInterval(86401)))
        XCTAssertTrue(EventEngine.merge(signals: [poll], personal: [], into: [], now: now.addingTimeInterval(86401)).isEmpty)
    }
    func testPublicAPIRequiresExplicitXAttribution() throws {
        let history = Data(#"{"data":[{"text":"Reset all propagated","announced_at":"2027-01-15T08:00:00Z","source":{"type":"observed","url":"https://x.com/thsottiaux/status/1"}}]}"#.utf8)
        let status = Data(#"{"data":{"active_watch":null,"scheduled_reset":null}}"#.utf8)
        XCTAssertTrue(try CodexResetsSource.parse(history: history,status: status,now: now).isEmpty)
    }
    func testRadarPollRelatedReplyAndStaleFail() throws {
        let raw = #"{"profile":{"handle":"thsottiaux"},"stale":false,"tweets":[{"id":"1","url":"https://x.com/thsottiaux/status/1","text":"I accept your vote","at":"2027-01-15T08:00:00Z","tibo_lane":"reset_related"}]}"#
        XCTAssertEqual(try TiboRadarSource.parse(Data(raw.utf8),now: now).first?.behavior, .poll)
        XCTAssertThrowsError(try TiboRadarSource.parse(Data(raw.replacingOccurrences(of: "false", with: "true").utf8),now: now))
    }
}
