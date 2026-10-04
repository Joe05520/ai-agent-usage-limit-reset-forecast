import Foundation

public enum DateParsing {
    public static func parse(_ text: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: text) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: text) { return date }
        for pattern in ["EEE, dd MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm:ss zzz", "yyyy-MM-dd"] {
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = pattern
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }
    public static func countdown(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return L10n.t("Reset time unavailable") }
        let seconds = Int(date.timeIntervalSince(now))
        guard seconds > 0 else { return L10n.t("Reset due · awaiting provider refresh") }
        let minutes = seconds / 60, hours = minutes / 60, days = hours / 24
        if days > 0 { return L10n.f("Resets in %dd %dh", days, hours % 24) }
        if hours > 0 { return L10n.f("Resets in %dh %dm", hours, minutes % 60) }
        return L10n.f("Resets in %dm", max(1, minutes))
    }
}
