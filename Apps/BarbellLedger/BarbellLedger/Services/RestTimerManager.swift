import Foundation
import Observation
import UserNotifications

@MainActor
@Observable
final class RestTimerManager: NSObject, UNUserNotificationCenterDelegate {
    private let notificationIdentifier = "barbellledger.rest.complete"
    private let endDateKey = "barbellledger.rest.endDate"
    private let durationKey = "barbellledger.rest.duration"

    var endDate: Date?
    var duration: TimeInterval = 90
    var authorizationStatus: UNAuthorizationStatus = .notDetermined
    var message: String?

    /// Incremented by every start/stop so a start suspended on a permission await cannot revive a cancelled timer.
    private var generation = 0

    var isRunning: Bool { endDate?.timeIntervalSinceNow ?? 0 > 0 }

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        let storedEnd = UserDefaults.standard.object(forKey: endDateKey) as? Date
        if let storedEnd, storedEnd > .now {
            endDate = storedEnd
            duration = UserDefaults.standard.double(forKey: durationKey)
        } else {
            clearStoredTimer()
        }
        Task { await refreshPermission() }
    }

    func remaining(at date: Date = .now) -> TimeInterval {
        max(0, endDate?.timeIntervalSince(date) ?? 0)
    }

    func start(seconds: TimeInterval) async {
        guard seconds > 0 else { return }
        message = nil
        generation += 1
        let token = generation
        let center = UNUserNotificationCenter.current()
        await refreshPermission()
        if authorizationStatus == .notDetermined {
            do {
                _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                message = "Notification permission could not be requested: \(error.localizedDescription)"
            }
            await refreshPermission()
        }
        guard token == generation else { return }

        duration = seconds
        let end = Date().addingTimeInterval(seconds)
        endDate = end
        UserDefaults.standard.set(end, forKey: endDateKey)
        UserDefaults.standard.set(seconds, forKey: durationKey)
        center.removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [notificationIdentifier])

        guard authorizationStatus == .authorized || authorizationStatus == .provisional || authorizationStatus == .ephemeral else {
            message = "The timer is running in BarbellLedger. Enable notifications in Settings to hear it when the app is backgrounded."
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Rest complete"
        content.body = "Your \(seconds.clockString) rest is over. Your next set is ready."
        content.sound = .default
        content.userInfo = ["kind": "rest-complete"]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        let request = UNNotificationRequest(identifier: notificationIdentifier, content: content, trigger: trigger)
        do {
            try await center.add(request)
            // stop() ran while scheduling: do not leave this alert behind. A newer start() reuses the
            // identifier and replaces this request on its own.
            if endDate == nil {
                center.removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
            }
        } catch {
            guard token == generation else { return }
            message = "The in-app timer is running, but the background alert could not be scheduled: \(error.localizedDescription)"
        }
    }

    func stop() {
        generation += 1
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [notificationIdentifier])
        clearStoredTimer()
        message = nil
    }

    func refreshPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    private func clearStoredTimer() {
        endDate = nil
        UserDefaults.standard.removeObject(forKey: endDateKey)
        UserDefaults.standard.removeObject(forKey: durationKey)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
