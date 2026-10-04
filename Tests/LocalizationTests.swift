import XCTest
#if SWIFT_PACKAGE
@testable import SentinelCore
#else
@testable import OpenAIUsageSentinel
#endif

final class LocalizationTests: XCTestCase {
    func testCatalogIsBundledAndAllLanguagesComplete() {
        XCTAssertGreaterThan(L10n.catalog.count, 180)
        for (key, translations) in L10n.catalog {
            XCTAssertEqual(Set(translations.keys), Set(AppLanguage.allCases.map(\.rawValue)), key)
            for language in AppLanguage.allCases { XCTAssertFalse(L10n.t(key, language: language).isEmpty, key) }
        }
    }
    func testAllFormatParametersArePreserved() throws {
        let regex = try NSRegularExpression(pattern: "%[@d]")
        func tokens(_ text: String) -> [String] {
            regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { String(text[Range($0.range, in: text)!]) }
        }
        for (key, values) in L10n.catalog { for text in values.values { XCTAssertEqual(tokens(key), tokens(text), key) } }
    }
    func testFourRequestedLanguagesHaveDistinctCaptions() {
        let expected: [AppLanguage: String] = [.traditionalChinese: "設定", .simplifiedChinese: "设置", .japanese: "設定", .korean: "설정"]
        for (language, value) in expected { XCTAssertEqual(L10n.t("Settings", language: language), value) }
        XCTAssertEqual(AppLanguage.allCases.map(\.label), ["English", "繁體中文", "简体中文", "日本語", "한국어"])
    }
    func testUnknownSourceNamesAndWordsStayOriginal() {
        for language in AppLanguage.allCases { XCTAssertEqual(L10n.t("Astra preview quota", language: language), "Astra preview quota") }
    }
    func testLegacySettingsAndLanguagePersistence() throws {
        var old = AppSettings(); old.usageInterval = 120; old.reminders.warningPercent = 30
        var dictionary = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as! [String: Any]
        dictionary.removeValue(forKey: "appLanguage")
        var restored = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: dictionary))
        XCTAssertEqual(restored.language, .english); XCTAssertEqual(restored.usageInterval, 120); XCTAssertEqual(restored.reminders.warningPercent, 30)
        for language in AppLanguage.allCases {
            restored.language = language
            XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(restored)).language, language)
        }
    }
    func testDynamicPercentageCountdownAndStyleLocalization() {
        let original = L10n.language; defer { L10n.language = original }
        let now = Date()
        for language in AppLanguage.allCases {
            L10n.language = language
            XCTAssertTrue(L10n.f("Low quota: ≤%d%% remaining", 30).contains("30%"))
            XCTAssertEqual(MenuBarStyle.standard.label, L10n.t("Standard", language: language))
            XCTAssertFalse(DateParsing.countdown(now.addingTimeInterval(7200), now: now).isEmpty)
            var settings = AppSettings(); settings.language = language
            XCTAssertEqual(MenuBarDisplay.title(usage: nil, available: false, signalCount: 0, settings: settings), L10n.t("◉ Usage ?", language: language))
        }
    }
    func testNewQuotaNotificationUsesChosenLanguage() {
        let original = L10n.language; defer { L10n.language = original }
        let now = Date(); let state = DemoScenarios.usage(20, at: now, resetAt: now.addingTimeInterval(86400))
        var engine = UsageReminderEngine(); engine.observe(state)
        let reminder = engine.pending(state, settings: .init(), now: now)[0]
        for language in AppLanguage.allCases {
            L10n.language = language
            let copy = NotificationText.reminder(reminder, mock: true)
            XCTAssertEqual(copy.title, "[MOCK] " + L10n.t("Low quota reminder", language: language))
            XCTAssertTrue(copy.body.contains("20%")); XCTAssertTrue(copy.body.contains(state.source))
            XCTAssertFalse(copy.body.contains("%@")); XCTAssertFalse(copy.body.contains("%d"))
        }
    }
    func testResetNotificationClassificationRemainsStableAcrossLanguages() {
        let original = L10n.language; defer { L10n.language = original }
        let event = DemoScenarios.run(2)[0]
        for language in AppLanguage.allCases {
            L10n.language = language
            let copy = NotificationText.event(event, mock: true)
            XCTAssertTrue(copy.title.contains(L10n.t("⚡ Unexpected usage reset detected", language: language)))
            XCTAssertTrue(copy.body.contains(event.product)); XCTAssertEqual(event.type.rawValue, "accountUnexpected")
        }
    }
    func testAppExplanationsTranslateWithoutChangingStoredEvidence() {
        let original = L10n.language; defer { L10n.language = original }
        let event = DemoScenarios.run(2)[0]; let snippet = event.sources[0].snippet
        L10n.language = .korean
        XCTAssertNotEqual(L10n.explanation(event.explanation), event.explanation)
        XCTAssertEqual(event.sources[0].snippet, snippet)
    }
    func testDatesUseSelectedLocale() {
        let original = L10n.language; defer { L10n.language = original }
        let date = Date(timeIntervalSince1970: 1791000000)
        L10n.language = .english; let english = date.localizedFormatted(date: .complete, time: .omitted)
        L10n.language = .japanese; let japanese = date.localizedFormatted(date: .complete, time: .omitted)
        XCTAssertNotEqual(english, japanese); XCTAssertTrue(japanese.contains("年"))
    }
    func testFormatterUsesSettingsLanguageInsteadOfAnotherContext() {
        let original = L10n.language; defer { L10n.language = original }
        L10n.language = .korean
        var settings = AppSettings()
        XCTAssertEqual(MenuBarDisplay.title(usage: nil, available: false, signalCount: 0, settings: settings), "◉ Usage ?")
        settings.language = .japanese
        XCTAssertEqual(MenuBarDisplay.title(usage: nil, available: false, signalCount: 0, settings: settings), "◉ 使用状況 ?")
        XCTAssertTrue(MenuBarDisplay.tooltip(usage: MenuBarDisplay.previewUsage, available: true, signalCount: 0, settings: settings).contains("週間"))
    }

}
