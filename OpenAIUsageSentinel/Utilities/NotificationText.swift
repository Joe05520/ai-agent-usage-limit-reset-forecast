import Foundation

public struct NotificationCopy: Sendable {
    public var title: String
    public var body: String
}
public enum NotificationText {
    public static func event(_ event: ResetEvent, mock: Bool) -> NotificationCopy {
        let prefix = mock ? "[MOCK] " : ""
        let title = event.ownAccountReset && !event.notifiedOwnReset
            ? prefix + L10n.t(event.reportCount > 0 ? "⚡ Reset signal strengthened" : "⚡ Unexpected usage reset detected")
            : prefix + "⚡ " + event.type.label
        let changes = event.affectedBuckets.compactMap { id -> String? in
            guard let before = event.beforeValue[id], let after = event.afterValue[id] else { return nil }
            return "\(id): \(Int(before))% → \(Int(after))%"
        }.joined(separator: "; ")
        let platforms = Array(Set(event.sources.map(\.platform))).sorted().joined(separator: ", ")
        let body = "\(event.product) · \(Int(event.confidence*100))% · \(event.level.label)\n"
            + (changes.isEmpty ? L10n.f("%d public reports", event.reportCount) : changes) + "\n"
            + L10n.f("Sources: %@. %@", platforms, L10n.t(event.level == .confirmed ? "Read source for eligibility." : "No official confirmation in monitored sources."))
        return NotificationCopy(title: title, body: body)
    }
    public static func reminder(_ reminder: UsageReminder, mock: Bool) -> NotificationCopy {
        NotificationCopy(
            title: (mock ? "[MOCK] " : "") + L10n.t(reminder.critical ? "Low quota · critical reminder" : "Low quota reminder"),
            body: L10n.f("%@ · %@: %@%% left\nYour reminder threshold: ≤%d%%\nNext regular reset: %@\nSource: %@ · observed %@",
                         reminder.bucket.product, L10n.t(reminder.bucket.name),
                         reminder.bucket.remainingPercent.formatted(.number.precision(.fractionLength(0...1)).locale(L10n.locale)),
                         Int(reminder.threshold), reminder.bucket.resetAt?.localizedFormatted() ?? L10n.t("unknown"),
                         reminder.bucket.source, reminder.observedAt.localizedFormatted(date: .omitted, time: .shortened))
        )
    }
}
