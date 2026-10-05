import Foundation
import UserNotifications

@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    var onOpen: ((UUID?) -> Void)?
    override init() { super.init(); center.delegate = self }
    func authorization() async -> String {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return "Authorized"
        case .denied: return "Denied · enable in System Settings → Notifications"
        case .notDetermined: return "Not requested"
        @unknown default: return "Unknown"
        }
    }
    func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }
    func send(_ event: ResetEvent, mock: Bool) async throws -> Bool {
        guard await authorization() == "Authorized" else { return false }
        let content = UNMutableNotificationContent()
        let copy = NotificationText.event(event, mock: mock)
        content.title = copy.title; content.body = copy.body
        content.sound = .default
        content.userInfo = ["eventID": event.id.uuidString]
        content.threadIdentifier = event.id.uuidString
        try await center.add(UNNotificationRequest(identifier: "\(event.id)-\(event.level.rank)-\(event.ownAccountReset)", content: content, trigger: nil))
        return true
    }
    func sendReminder(_ reminder: UsageReminder, mock: Bool) async throws -> Bool {
        guard await authorization() == "Authorized" else { return false }
        let content = UNMutableNotificationContent()
        let copy = NotificationText.reminder(reminder, mock: mock)
        content.title = copy.title; content.body = copy.body
        content.sound = .default
        content.userInfo = ["kind": "usageReminder", "bucketID": reminder.bucket.id]
        content.threadIdentifier = "usage-reminders"
        try await center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: nil))
        return true
    }
    func deliverySummary() async -> String {
        let delivered = await center.deliveredNotifications()
        return L10n.f("Delivered notifications in Notification Center: %d\n", delivered.count) + delivered.suffix(8).map { $0.request.content.title + " · " + $0.date.localizedFormatted() }.joined(separator: "\n")
    }
    func test() async throws {
        guard await requestPermission() else { throw SentinelError.unavailable(L10n.t("Notification permission not granted.")) }
        let content = UNMutableNotificationContent(); content.title = "AI Usage Sentinel · " + L10n.t("Notification test"); content.body = L10n.t("Notification test delivered. Click to open event history."); content.sound = .default
        try await center.add(UNNotificationRequest(identifier: "sentinel-test", content: content, trigger: nil))
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner, .sound, .list]) }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = (response.notification.request.content.userInfo["eventID"] as? String).flatMap(UUID.init(uuidString:))
        Task { @MainActor [weak self] in self?.onOpen?(id) }
        completionHandler()
    }
}
