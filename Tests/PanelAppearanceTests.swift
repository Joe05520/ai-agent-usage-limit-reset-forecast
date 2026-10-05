import XCTest
#if SWIFT_PACKAGE
@testable import SentinelCore
#else
@testable import OpenAIUsageSentinel
#endif
final class PanelAppearanceTests: XCTestCase {
    func testLegacySettingsRetainPreferencesAndDefaultToProfessional() throws {
        var settings = AppSettings(); settings.usageInterval = 120; settings.reminders.stages = [40, 10]
        var data = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as! [String: Any]
        data.removeValue(forKey: "panelConfiguration")
        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: data))
        XCTAssertEqual(restored.panel.mode, .professional)
        XCTAssertEqual(restored.usageInterval, 120)
        XCTAssertEqual(restored.reminders.stages, [40, 10])
    }
    func testVisualSelectionsRoundTripWithoutChangingDetection() throws {
        for mode in PanelMode.allCases { for style in QuotaVisualStyle.allCases {
            var settings = AppSettings(); settings.panel.mode = mode; settings.panel.visualStyle = style; settings.panel.animations = false
            let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
            XCTAssertEqual(restored.panel, settings.panel)
            XCTAssertEqual(restored.threshold, 0.25); XCTAssertTrue(restored.notifyUnexpected)
        } }
    }
}
