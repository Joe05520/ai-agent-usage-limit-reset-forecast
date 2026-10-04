import Foundation

public enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case english = "en", traditionalChinese = "zh-Hant", simplifiedChinese = "zh-Hans", japanese = "ja", korean = "ko"
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .english: return "English"
        case .traditionalChinese: return "繁體中文"
        case .simplifiedChinese: return "简体中文"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        }
    }
    public var locale: Locale { Locale(identifier: rawValue) }
}

public enum L10n {
    private static let lock = NSLock()
    private static var selected = AppLanguage.english
    public static var language: AppLanguage {
        get { lock.lock(); defer { lock.unlock() }; return selected }
        set {
            lock.lock(); let changed = selected != newValue; selected = newValue; lock.unlock()
            if changed { NotificationCenter.default.post(name: .sentinelLanguageChanged, object: nil) }
        }
    }
    public static var locale: Locale { language.locale }
    static let catalog: [String: [String: String]] = {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "Translations", withExtension: "json"), let data = try? Data(contentsOf: url),
              let dictionary = try? JSONDecoder().decode([String: [String: String]].self, from: data) else { return [:] }
        return dictionary
    }()
    public static func t(_ key: String, language: AppLanguage? = nil) -> String {
        catalog[key]?[(language ?? Self.language).rawValue] ?? key
    }
    public static func f(_ key: String, _ values: CVarArg..., language: AppLanguage? = nil) -> String {
        String(format: t(key, language: language), locale: (language ?? Self.language).locale, arguments: values)
    }
    public static func explanation(_ text: String) -> String {
        var result = text
        // Only app-authored explanations; external titles/snippets are never passed here.
        for key in catalog.keys.filter({ $0.count > 40 }).sorted(by: { $0.count > $1.count }) where result.contains(key) {
            result = result.replacingOccurrences(of: key, with: t(key))
        }
        return result
    }
}

extension Notification.Name {
    static let sentinelLanguageChanged = Notification.Name("SentinelLanguageChanged")
}
public extension Date {
    func localizedFormatted(date: Date.FormatStyle.DateStyle = .abbreviated, time: Date.FormatStyle.TimeStyle = .shortened) -> String {
        formatted(Date.FormatStyle(date: date, time: time).locale(L10n.locale))
    }
}
