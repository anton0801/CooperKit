import Foundation
import UserNotifications

/// Local due-date reminders for the owner, rebuilt from the open handovers after every
/// change. Nothing is ever sent to the person who has the tools.
final class NotificationReminderScheduler: ReminderScheduling {
    private let center = UNUserNotificationCenter.current()
    private let prefix = "copperkit.due."

    func requestAuthorization(_ completion: @escaping (Bool) -> Void) {
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    func sync(handovers: [Handover], toolNames: [UUID: String], enabled: Bool, now: Date) {
        center.getPendingNotificationRequests { [center, prefix] pending in
            let ours = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: ours)
            guard enabled else { return }

            let upcoming = handovers
                .filter { !$0.isClosed && $0.dueAt > now }
                .sorted { $0.dueAt < $1.dueAt }
                .prefix(60) // iOS keeps at most 64 pending requests per app

            for handover in upcoming {
                let content = UNMutableNotificationContent()
                content.title = handover.mode == .loan ? "Due back from \(handover.recipientName)" : "Personal use is due back"
                let units = handover.totalOutstanding
                content.body = "\(handover.purpose) · \(units == 1 ? "1 unit" : "\(units) units") still out."
                content.sound = .default
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = handover.dueTimeZone
                let parts = calendar.dateComponents(in: handover.dueTimeZone, from: handover.dueAt)
                var trigger = DateComponents()
                trigger.timeZone = handover.dueTimeZone
                trigger.year = parts.year
                trigger.month = parts.month
                trigger.day = parts.day
                trigger.hour = parts.hour
                trigger.minute = parts.minute
                let request = UNNotificationRequest(
                    identifier: prefix + handover.id.uuidString, content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: trigger, repeats: false)
                )
                center.add(request)
            }
        }
    }
}

/// Used by tests and previews.
final class NoReminders: ReminderScheduling {
    func sync(handovers: [Handover], toolNames: [UUID: String], enabled: Bool, now: Date) {}
    func requestAuthorization(_ completion: @escaping (Bool) -> Void) { completion(false) }
}
