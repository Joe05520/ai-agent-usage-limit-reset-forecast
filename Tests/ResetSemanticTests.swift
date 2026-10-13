import XCTest
#if SWIFT_PACKAGE
@testable import SentinelCore
#else
@testable import OpenAIUsageSentinel
#endif
final class ResetSemanticTests: XCTestCase {
    func testMeaningAndAbstention() {
        let examples = [("Codex reset has been processed", "completed"), ("My quota returned to 100%", "accountReport"), ("Global reset landing tomorrow", "forecast"), ("Vote for an update or a reset", "poll"), ("No global reset is planned", "negative"), ("My scheduled reset arrived", "regular"), ("Reset your API key", "irrelevant"), ("Hopefully we get a reset", "uncertain")]
        for (text, label) in examples { XCTAssertEqual(ResetSemanticModel.assess(text)?.label, label, text) }
        XCTAssertEqual(ResetSemanticModel.assess("Codex reset has not been processed")?.label, "negative")
        XCTAssertEqual(ResetSemanticModel.assess("My scheduled reset returned to 100%")?.label, "regular")
        XCTAssertNil(ResetSemanticModel.assess("Codex global reset"))
        XCTAssertNil(ResetSemanticModel.assess("額度突然恢復，是否有其他人也一樣？"))
    }
    func testSemanticsDoNotChangeOwnEvidenceAndCannotBoostRumors() {
        let now = Date()
        var source = DemoScenarios.reports(1, platform: "Reddit", now: now)[0].source
        source.title = "Codex"; source.snippet = "No global reset is planned"
        XCTAssertNil(SignalClassifier.classify(source))
        var watched = source
        watched.url = URL(string: "https://x.com/thsottiaux/status/123456")!; watched.author = "thsottiaux"; watched.snippet = "Put the reset in the bag. All propagated."
        XCTAssertEqual(ResetWatchPolicy.classify(watched)?.behavior, .suspectedGlobal)
        XCTAssertEqual(EventEngine.score(sources: [source], ownReset: false, now: now), 0)
        XCTAssertEqual(EventEngine.score(sources: [source], ownReset: true, now: now), 0.6)
        source.snippet = "Hopefully we get a reset"
        XCTAssertLessThan(EventEngine.score(sources: [source], ownReset: false, now: now), 0.1)
        source.official = true; source.snippet = "Global reset landing tomorrow"
        XCTAssertLessThan(EventEngine.score(sources: [source], ownReset: false, now: now), 0.9)
    }
}
