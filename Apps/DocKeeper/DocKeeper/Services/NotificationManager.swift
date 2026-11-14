import Foundation
import SwiftUI
import UserNotifications

enum ReminderError: LocalizedError {
    case permissionDenied
    case noFutureReminder

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Notification permission is off. Allow notifications in Settings to receive local reminders."
        case .noFutureReminder:
            "No reminder time is in the future. Choose a later due date or fewer lead days."
        }
    }
}

@MainActor
final class NotificationManager: ObservableObject {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private var center: UNUserNotificationCenter { .current() }

    init() {
        Task { await refreshAuthorization() }
    }

    func refreshAuthorization() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    func requestPermission() async -> Bool {
        do {
            if authorizationStatus == .notDetermined {
                _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            }
            await refreshAuthorization()
            return authorizationStatus == .authorized || authorizationStatus == .provisional
        } catch {
            await refreshAuthorization()
            return false
        }
    }

    @discardableResult
    func rescheduleReminders(for document: DocumentRecord) async throws -> Int {
        guard document.remindersEnabled else {
            cancelReminders(for: document)
            return 0
        }
        guard await requestPermission() else {
            cancelReminders(for: document)
            throw ReminderError.permissionDenied
        }

        var requests: [UNNotificationRequest] = []
        if let expiryDate = document.expiryDate,
           let request = makeRequest(
            for: document,
            dueDate: expiryDate,
            suffix: "expiry",
            title: "Warranty or expiry coming up"
           ) {
            requests.append(request)
        }
        if let renewalDate = document.renewalDate,
           let request = makeRequest(
            for: document,
            dueDate: renewalDate,
            suffix: "renewal",
            title: "Renewal coming up"
           ) {
            requests.append(request)
        }
        guard !requests.isEmpty else {
            cancelReminders(for: document)
            throw ReminderError.noFutureReminder
        }

        do {
            for request in requests {
                try await center.add(request)
            }
            let scheduledIdentifiers = Set(requests.map(\.identifier))
            let staleIdentifiers = identifiers(for: document).filter { !scheduledIdentifiers.contains($0) }
            center.removePendingNotificationRequests(withIdentifiers: staleIdentifiers)
            return requests.count
        } catch {
            cancelReminders(for: document)
            throw error
        }
    }

    func cancelReminders(for document: DocumentRecord) {
        cancelReminders(forDocumentID: document.id)
    }

    func cancelReminders(forDocumentID id: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers(forDocumentID: id))
    }

    private func makeRequest(
        for document: DocumentRecord,
        dueDate: Date,
        suffix: String,
        title: String
    ) -> UNNotificationRequest? {
        let calendar = Calendar.current
        guard let leadDate = calendar.date(
            byAdding: .day,
            value: -max(0, document.reminderLeadDays),
            to: dueDate
        ) else { return nil }
        let triggerDate = calendar.date(
            bySettingHour: 9,
            minute: 0,
            second: 0,
            of: leadDate
        ) ?? leadDate
        guard triggerDate > .now else { return nil }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = "\(document.title) is due \(dueDate.formatted(date: .abbreviated, time: .omitted))."
        content.sound = .default
        content.userInfo = ["documentID": document.id.uuidString]

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
        return UNNotificationRequest(
            identifier: "\(document.id.uuidString).\(suffix)",
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
    }

    private func identifiers(for document: DocumentRecord) -> [String] {
        identifiers(forDocumentID: document.id)
    }

    private func identifiers(forDocumentID id: UUID) -> [String] {
        [
            "\(id.uuidString).expiry",
            "\(id.uuidString).renewal"
        ]
    }
}
