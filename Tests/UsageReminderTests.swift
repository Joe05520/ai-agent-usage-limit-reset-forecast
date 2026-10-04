import XCTest
#if SWIFT_PACKAGE
@testable import SentinelCore
#else
@testable import OpenAIUsageSentinel
#endif

final class UsageReminderTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1791000000)
    func snapshot(_ remaining: Double, seconds: Double = 0) -> UsageState {
        DemoScenarios.usage(remaining, at: now.addingTimeInterval(seconds), resetAt: now.addingTimeInterval(3*86400))
    }
    func pending(_ engine: inout UsageReminderEngine, _ remaining: Double, seconds: Double = 0, settings: UsageReminderSettings = .init()) -> [UsageReminder] {
        let state = snapshot(remaining, seconds: seconds); engine.observe(state)
        return engine.pending(state, settings: settings, now: now.addingTimeInterval(seconds))
    }
    func testCrossingWarningAndCriticalOnlyOnce() {
        var engine = UsageReminderEngine()
        XCTAssertTrue(pending(&engine, 30).isEmpty)
        let warning = pending(&engine, 20, seconds: 1); XCTAssertEqual(warning.count, 1); XCTAssertFalse(warning[0].critical)
        engine.markDelivered(warning[0])
        XCTAssertTrue(pending(&engine, 19, seconds: 2).isEmpty)
        let critical = pending(&engine, 5, seconds: 3); XCTAssertEqual(critical.count, 1); XCTAssertTrue(critical[0].critical)
        engine.markDelivered(critical[0]); XCTAssertTrue(pending(&engine, 4, seconds: 4).isEmpty)
    }
    func testInitialCriticalCombinesBothThresholds() {
        var engine = UsageReminderEngine(); let alert = pending(&engine, 3)[0]
        XCTAssertEqual(alert.coveredThresholds, [5,20]); engine.markDelivered(alert)
        XCTAssertTrue(pending(&engine, 12, seconds: 1).isEmpty)
    }
    func testDeniedDeliveryRetries() {
        var engine = UsageReminderEngine(); XCTAssertEqual(pending(&engine, 20).count, 1)
        XCTAssertEqual(pending(&engine, 19, seconds: 1).count, 1)
    }
    func testPersistencePreventsRestartDuplicates() throws {
        var engine = UsageReminderEngine(); engine.markDelivered(pending(&engine, 20)[0])
        var restored = try JSONDecoder().decode(UsageReminderEngine.self, from: JSONEncoder().encode(engine))
        XCTAssertTrue(pending(&restored, 19, seconds: 1).isEmpty)
    }
    func testUnexpectedFullRecoveryRearmsSameSchedule() {
        var engine = UsageReminderEngine(); engine.markDelivered(pending(&engine, 20)[0])
        XCTAssertTrue(pending(&engine, 100, seconds: 1).isEmpty)
        XCTAssertEqual(pending(&engine, 20, seconds: 2).count, 1)
    }
    func testSmallOscillationDoesNotRearm() {
        var engine = UsageReminderEngine(); engine.markDelivered(pending(&engine, 20)[0])
        XCTAssertTrue(pending(&engine, 25, seconds: 1).isEmpty)
        XCTAssertTrue(pending(&engine, 20, seconds: 2).isEmpty)
    }
    func testChangedScheduleRearms() {
        var engine = UsageReminderEngine(); engine.markDelivered(pending(&engine, 20)[0])
        var next = snapshot(19, seconds: 1); next.buckets[0].resetAt = now.addingTimeInterval(10*86400); engine.observe(next)
        XCTAssertEqual(engine.pending(next, settings: .init(), now: now).count, 1)
    }
    func testAccountChangeHasSeparateReminder() {
        var engine = UsageReminderEngine(); engine.markDelivered(pending(&engine, 20)[0])
        var next = snapshot(19, seconds: 1); next.accountFingerprint = "another-account"; engine.observe(next)
        XCTAssertEqual(engine.pending(next, settings: .init(), now: now).count, 1)
    }
    func testDisabledExcludedSnoozedAndResume() {
        var engine = UsageReminderEngine(); var settings = UsageReminderSettings()
        settings.enabled = false; XCTAssertTrue(pending(&engine, 20, settings: settings).isEmpty)
        settings.enabled = true; settings.excludedBucketIDs = [snapshot(20).buckets[0].id]
        XCTAssertTrue(pending(&engine, 20, settings: settings).isEmpty)
        settings.excludedBucketIDs = []; settings.snoozedUntil = now.addingTimeInterval(3600)
        XCTAssertTrue(pending(&engine, 20, settings: settings).isEmpty)
        settings.snoozedUntil = now.addingTimeInterval(-1)
        XCTAssertEqual(pending(&engine, 20, settings: settings).count, 1)
    }
    func testOldSnapshotsAndExpiredResetDoNotNotify() {
        var engine = UsageReminderEngine(); let state = snapshot(20); engine.observe(state)
        XCTAssertTrue(engine.pending(state, settings: .init(), now: now.addingTimeInterval(601)).isEmpty)
        var expired = snapshot(19, seconds: 1); expired.buckets[0].resetAt = now.addingTimeInterval(-1); engine.observe(expired)
        XCTAssertTrue(engine.pending(expired, settings: .init(), now: now).isEmpty)
    }
    func testCustomThresholdAndCriticalOff() {
        var engine = UsageReminderEngine(); var settings = UsageReminderSettings(); settings.warningPercent = 35; settings.criticalEnabled = false
        XCTAssertEqual(pending(&engine, 35, settings: settings).first?.threshold, 35)
        XCTAssertFalse(pending(&engine, 1, seconds: 1, settings: settings)[0].critical)
    }
    func testBackwardCompatibleSettingsPreservePreferences() throws {
        var settings = AppSettings(); settings.reddit = false; settings.threshold = 0.60; settings.cliPath = "/custom/codex"
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as! [String: Any]
        object.removeValue(forKey: "reminderConfiguration")
        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertFalse(restored.reddit); XCTAssertEqual(restored.threshold, 0.60); XCTAssertEqual(restored.cliPath, "/custom/codex"); XCTAssertEqual(restored.reminders.warningPercent, 20)
        settings.reminders.warningPercent = 33
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings)).reminders.warningPercent, 33)
    }
    func testOutOfOrderCannotOverwriteDeliveredCycle() {
        var engine = UsageReminderEngine(); let warning = pending(&engine, 20, seconds: 2)[0]; engine.markDelivered(warning)
        engine.observe(snapshot(100, seconds: 1))
        XCTAssertTrue(pending(&engine, 19, seconds: 3).isEmpty)
    }
    func testMultipleBucketsAreIndependent() {
        var engine = UsageReminderEngine(); var state = snapshot(20)
        var other = state.buckets[0]; other.id = "future.hourly"; other.name = "Hourly"; other.windowDuration = 3600; state.buckets.append(other)
        engine.observe(state); let alerts = engine.pending(state, settings: .init(), now: now)
        XCTAssertEqual(alerts.count, 2); XCTAssertNotEqual(alerts[0].id, alerts[1].id)
        engine.markDelivered(alerts[0]); XCTAssertEqual(engine.pending(state, settings: .init(), now: now).count, 1)
    }
    func testDailyTrendExcludesRecoveryAndLongGaps() {
        let history = [snapshot(30), snapshot(20, seconds: 300), snapshot(100, seconds: 600), snapshot(95, seconds: 900), snapshot(80, seconds: 3000)]
        XCTAssertEqual(ObservedUsageTrend.consumedPoints(bucketID: history[0].buckets[0].id, history: history, now: now.addingTimeInterval(3000)), 15)
    }
    func testDailyTrendExcludesOtherAccountAndSchedule() {
        let first = snapshot(30); var second = snapshot(20, seconds: 300); second.accountFingerprint = "other"
        XCTAssertNil(ObservedUsageTrend.consumedPoints(bucketID: first.buckets[0].id, history: [first, second], now: now.addingTimeInterval(300)))
        second.accountFingerprint = first.accountFingerprint; second.buckets[0].resetAt = now.addingTimeInterval(7*86400)
        XCTAssertNil(ObservedUsageTrend.consumedPoints(bucketID: first.buckets[0].id, history: [first, second], now: now.addingTimeInterval(300)))
    }
    func testChangedThresholdCanNotifyNewPreference() {
        var engine = UsageReminderEngine(); engine.markDelivered(pending(&engine, 20)[0])
        var settings = UsageReminderSettings(); settings.warningPercent = 30
        XCTAssertEqual(pending(&engine, 19, seconds: 1, settings: settings).first?.threshold, 30)
    }
    func testOnePercentWarningAndZeroPercentCritical() {
        var engine = UsageReminderEngine(); var settings = UsageReminderSettings(); settings.warningPercent = 1
        XCTAssertEqual(settings.thresholds, [0, 1])
        let warning = pending(&engine, 1, settings: settings)[0]; XCTAssertFalse(warning.critical); engine.markDelivered(warning)
        XCTAssertTrue(pending(&engine, 0, seconds: 1, settings: settings)[0].critical)
    }

    func testFiveStagesNotifyInOrderAndPersist() throws {
        var engine = UsageReminderEngine(); var settings = UsageReminderSettings(); settings.stages = [50,30,20,10,5]
        XCTAssertTrue(pending(&engine, 80, settings: settings).isEmpty)
        for (index, value) in settings.stages.enumerated() {
            let alerts = pending(&engine, value, seconds: Double(index + 1), settings: settings)
            XCTAssertEqual(alerts.count, 1); XCTAssertEqual(alerts.first?.threshold, value)
            XCTAssertEqual(alerts.first?.critical, index == 4)
            engine.markDelivered(alerts[0])
            engine = try JSONDecoder().decode(UsageReminderEngine.self, from: JSONEncoder().encode(engine))
        }
        XCTAssertTrue(pending(&engine, 1, seconds: 10, settings: settings).isEmpty)
        _ = pending(&engine, 100, seconds: 11, settings: settings)
        XCTAssertEqual(pending(&engine, 50, seconds: 12, settings: settings).first?.threshold, 50)
    }
    func testFiveStageJumpProducesOneDelivery() {
        var engine = UsageReminderEngine(); var settings = UsageReminderSettings(); settings.stages = [50,30,20,10,5]
        let alerts = pending(&engine, 3, settings: settings)
        XCTAssertEqual(alerts.count, 1); XCTAssertEqual(alerts[0].threshold, 5)
        XCTAssertEqual(alerts[0].coveredThresholds, [5,10,20,30,50]); engine.markDelivered(alerts[0])
        XCTAssertTrue(pending(&engine, 20, seconds: 1, settings: settings).isEmpty)
    }
    func testLegacyTwoStageMigrationPreservesThirtyAndTen() throws {
        var settings = UsageReminderSettings(); settings.warningPercent = 30; settings.criticalPercent = 10
        let restored = try JSONDecoder().decode(UsageReminderSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(restored.stages, [30,10]); XCTAssertNil(restored.stagedThresholds)
        var migrated = restored; migrated.addStage(); XCTAssertEqual(migrated.stages, [50,30,10])
    }
    func testStageLimitValidationAndDeletion() {
        var settings = UsageReminderSettings(); settings.stages = [50,30,20,10,5,1,30,-1,100,.nan]
        XCTAssertEqual(settings.stages, [50,30,20,10,5]); settings.addStage(); XCTAssertEqual(settings.stages.count, 5)
        settings.stages = [0]; XCTAssertFalse(settings.hasCriticalStage)
        var engine = UsageReminderEngine(); XCTAssertFalse(pending(&engine, 0, settings: settings)[0].critical)
        settings.stages = []; XCTAssertTrue(pending(&engine, 0, seconds: 1, settings: settings).isEmpty)
        settings.addStage(); XCTAssertEqual(settings.stages, [50])
    }

}
