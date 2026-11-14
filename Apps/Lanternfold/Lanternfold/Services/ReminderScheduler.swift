import Foundation
import UserNotifications

/// Local reminders for the daily garden. Nothing is sent to a server; the next few days are
/// scheduled on the device and refreshed whenever the app is opened.
@MainActor
enum ReminderScheduler {
    static let enabledKey = "dailyReminder"
    static let minutesKey = "dailyReminderMinutes"
    private static let prefix = "lanternfold-daily-"
    private static let daysAhead = 7

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    /// Minutes after midnight; 9:00 by default.
    static var minutes: Int {
        UserDefaults.standard.object(forKey: minutesKey) as? Int ?? 9 * 60
    }

    /// Asks for permission if needed and turns reminders on. Returns false when the player declined.
    static func enable() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted: Bool
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            granted = true
        case .notDetermined:
            granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        default:
            granted = false
        }
        UserDefaults.standard.set(granted, forKey: enabledKey)
        return granted
    }

    static func disable() {
        UserDefaults.standard.set(false, forKey: enabledKey)
        clear()
    }

    private static func clear() {
        let center = UNUserNotificationCenter.current()
        let ids = (-1...daysAhead + 1).map { prefix + DayStamp.today.adding(days: $0).key }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// Schedules one reminder for each of the coming days, skipping today when it is already solved.
    static func refresh(todaySolved: Bool) async {
        guard isEnabled else { return }
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional || status == .ephemeral else {
            UserDefaults.standard.set(false, forKey: enabledKey)
            return
        }
        clear()
        let today = DayStamp.today
        for offset in 0..<daysAhead {
            if offset == 0 && todaySolved { continue }
            let day = today.adding(days: offset)
            let source = PuzzleSource.daily(day)
            let request = source.request
            let content = UNMutableNotificationContent()
            content.title = "Today's garden is ready"
            content.body = "\(source.title) · \(request.size)×\(request.size) \(request.difficulty?.title ?? "")"
            content.sound = .default
            var when = DateComponents()
            when.year = day.year
            when.month = day.month
            when.day = day.day
            when.hour = minutes / 60
            when.minute = minutes % 60
            let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: prefix + day.key, content: content, trigger: trigger))
        }
    }
}
