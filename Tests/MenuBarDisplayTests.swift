import XCTest
#if SWIFT_PACKAGE
@testable import SentinelCore
#else
@testable import OpenAIUsageSentinel
#endif

final class MenuBarDisplayTests: XCTestCase {
    var usage: UsageState { MenuBarDisplay.previewUsage }
    func title(_ settings: AppSettings, count: Int = 1, available: Bool = true) -> String {
        MenuBarDisplay.title(usage: usage, available: available, signalCount: count, settings: settings)
    }
    func testAllStyleContracts() {
        let examples: [(MenuBarStyle, String)] = [(.standard, "◉ 5h 72% · W 61%"), (.compact, "5h72% · W61%"), (.percentages, "72% / 61%"), (.singleQuota, "5h 72%"), (.icon, "◉")]
        for (style, expected) in examples {
            var settings = AppSettings(); settings.appearance.style = style
            XCTAssertEqual(title(settings), expected)
        }
    }
    func testSignalCountCanBeHiddenForEveryStyle() {
        for style in MenuBarStyle.allCases {
            var settings = AppSettings(); settings.appearance.style = style
            settings.appearance.showSignalCount = true
            XCTAssertTrue(title(settings, count: 3).hasSuffix(" · ⚡3"))
            XCTAssertFalse(title(settings, count: 0).contains("⚡"))
            settings.appearance.showSignalCount = false
            XCTAssertFalse(title(settings, count: 3).contains("⚡"))
        }
    }
    func testUnavailableNeverShowsOldPercentagesInAnyStyle() {
        for style in MenuBarStyle.allCases {
            var settings = AppSettings(); settings.appearance.style = style
            XCTAssertEqual(title(settings, available: false), "◉ Usage ?")
        }
    }
    func testSingleSelectedBucketOverridesMultipleQuotaVisibilitySwitches() {
        var settings = AppSettings(); settings.appearance.style = .singleQuota
        settings.appearance.selectedBucketID = "preview.weekly"; settings.showWeekly = false; settings.showShort = false
        XCTAssertEqual(title(settings), "W 61%")
        settings.appearance.selectedBucketID = "removed-bucket"
        XCTAssertEqual(title(settings), "5h 72%")
    }
    func testWeeklyOnlyDoesNotInventShortWindow() {
        var weeklyOnly = usage; weeklyOnly.buckets.removeFirst()
        var settings = AppSettings(); settings.appearance.style = .percentages
        XCTAssertEqual(MenuBarDisplay.title(usage: weeklyOnly, available: true, signalCount: 0, settings: settings), "61%")
        settings.appearance.style = .standard
        XCTAssertEqual(MenuBarDisplay.title(usage: weeklyOnly, available: true, signalCount: 0, settings: settings), "◉ W 61%")
    }
    func testOrderIsStableAndVisibilityAppliesToMultipleStyles() {
        var reversed = usage; reversed.buckets.reverse()
        var settings = AppSettings(); settings.appearance.style = .percentages
        XCTAssertEqual(MenuBarDisplay.title(usage: reversed, available: true, signalCount: 0, settings: settings), "72% / 61%")
        settings.showShort = false; XCTAssertEqual(title(settings), "61%")
        settings.showWeekly = false; XCTAssertEqual(title(settings), "◉")
    }
    func testLegacySettingsMigrationPreservesIconPreferenceAndReminders() throws {
        var old = AppSettings(); old.showPercent = false; old.reminders.warningPercent = 30
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as! [String: Any]
        json.removeValue(forKey: "menuBarConfiguration")
        var decoded = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.appearance.style, .icon); XCTAssertFalse(decoded.appearance.showSignalCount)
        XCTAssertEqual(decoded.reminders.warningPercent, 30)
        decoded.appearance.style = .compact; decoded.appearance.showSignalCount = true
        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(decoded))
        XCTAssertEqual(restored.appearance.style, .compact); XCTAssertTrue(restored.appearance.showSignalCount)
        XCTAssertEqual(restored.reminders.warningPercent, 30)
    }
    func testAppearanceDoesNotChangeDetectionNotificationPreferences() {
        var settings = AppSettings(); let original = settings
        settings.appearance.style = .icon; settings.appearance.showSignalCount = false; settings.appearance.showBankedCredits = false
        XCTAssertEqual(settings.reminders, original.reminders); XCTAssertEqual(settings.notifyUnexpected, original.notifyUnexpected)
        XCTAssertEqual(settings.threshold, original.threshold); XCTAssertEqual(settings.usageInterval, original.usageInterval)
    }
    func testMockIsAlwaysExplicitlyMarked() {
        for style in MenuBarStyle.allCases {
            var settings = AppSettings(); settings.appearance.style = style
            XCTAssertTrue(MenuBarDisplay.title(usage: usage, available: true, signalCount: 0, settings: settings, mock: true).hasPrefix("[MOCK] "))
        }
    }
    func testIconTooltipAndPercentageLegendRemainUnderstandable() {
        var settings = AppSettings(); settings.appearance.style = .icon; settings.showWeekly = false; settings.showShort = false
        let tooltip = MenuBarDisplay.tooltip(usage: usage, available: true, signalCount: 2, settings: settings)
        XCTAssertTrue(tooltip.contains("5-hour: 72%")); XCTAssertTrue(tooltip.contains("Weekly: 61%")); XCTAssertFalse(tooltip.contains("reset signals"))
        settings.appearance.showSignalCount = true
        XCTAssertTrue(MenuBarDisplay.tooltip(usage: usage, available: true, signalCount: 2, settings: settings).contains("2 active reset signals"))
    }
}
