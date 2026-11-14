import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(Navigator.self) private var navigator
    @Environment(StoreManager.self) private var store
    @Query private var records: [PuzzleRecord]

    @AppStorage(SettingKey.showConflicts) private var showConflicts = true
    @AppStorage(SettingKey.dimBlocked) private var dimBlocked = true
    @AppStorage(SettingKey.lanternFirst) private var lanternFirst = false
    @AppStorage(SettingKey.showTimer) private var showTimer = true
    @AppStorage(SettingKey.haptics) private var haptics = true
    @AppStorage(SettingKey.sounds) private var sounds = true

    @AppStorage(ReminderScheduler.enabledKey) private var reminder = false
    @AppStorage(ReminderScheduler.minutesKey) private var reminderMinutes = 9 * 60

    @State private var exportDocument: ProgressDocument?
    @State private var exporting = false
    @State private var confirmingReset = false
    @State private var message: String?

    private var todaySolved: Bool {
        let key = PuzzleSource.daily(.today).key
        return records.contains { $0.key == key && $0.isComplete }
    }

    private static let privacyURL = URL(string: "https://yanmingyu92.github.io/automation-studio-ios/lanternfold/privacy.html")
    private static let supportURL = URL(string: "https://yanmingyu92.github.io/automation-studio-ios/lanternfold/support.html")

    var body: some View {
        Form {
            Section {
                Toggle("Show conflicts", isOn: $showConflicts)
                Toggle("Dot cells a lantern already rules out", isOn: $dimBlocked)
                Toggle("First tap places a lantern", isOn: $lanternFirst)
                Toggle("Show timer", isOn: $showTimer)
                Toggle("Sounds", isOn: $sounds)
                Toggle("Haptics", isOn: $haptics)
            } header: {
                Text("Play")
            } footer: {
                Text(lanternFirst ? "Tap order: lantern, mark, clear." : "Tap order: mark, lantern, clear. Drag across cells to mark several at once.")
            }

            Section {
                Toggle("Daily reminder", isOn: Binding(
                    get: { reminder },
                    set: { wanted in
                        Task {
                            if wanted {
                                if await ReminderScheduler.enable() {
                                    await ReminderScheduler.refresh(todaySolved: todaySolved)
                                } else {
                                    message = "Notifications are off for Lanternfold. Allow them in iOS Settings, then switch the reminder on again."
                                }
                            } else {
                                ReminderScheduler.disable()
                            }
                        }
                    }
                ))
                if reminder {
                    DatePicker("Time", selection: Binding(
                        get: {
                            Calendar.current.date(bySettingHour: reminderMinutes / 60, minute: reminderMinutes % 60, second: 0, of: .now) ?? .now
                        },
                        set: { date in
                            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                            reminderMinutes = (parts.hour ?? 9) * 60 + (parts.minute ?? 0)
                            Task { await ReminderScheduler.refresh(todaySolved: todaySolved) }
                        }
                    ), displayedComponents: .hourAndMinute)
                }
            } header: {
                Text("Reminder")
            } footer: {
                Text("One notification a day when the new garden is ready. Scheduled on this device; nothing is sent to a server.")
            }

            Section("Full Garden") {
                if store.isPro {
                    Label("Unlocked on this Apple Account", systemImage: "checkmark.seal.fill")
                } else {
                    Button("See the Full Garden") { navigator.showingPaywall = true }
                }
                Button("Restore purchase") {
                    Task {
                        await store.restorePurchases()
                        message = store.errorMessage ?? store.statusMessage
                    }
                }
                .disabled(store.isPurchasing)
            }

            Section {
                Button("Export progress as JSON") {
                    do {
                        exportDocument = try ProgressDocument(records: records)
                        exporting = true
                    } catch {
                        message = "Export failed: \(error.localizedDescription)"
                    }
                }
                .disabled(records.isEmpty)
                Button("Erase all progress", role: .destructive) { confirmingReset = true }
                    .disabled(records.isEmpty)
            } header: {
                Text("Your data")
            } footer: {
                Text("Puzzles, times and streaks are stored only on this device. Deleting the app deletes them.")
            }

            Section("About") {
                Button("How to play") { navigator.showingRules = true }
                if let url = Self.privacyURL {
                    Link("Privacy policy", destination: url)
                }
                if let url = Self.supportURL {
                    Link("Support", destination: url)
                }
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("Settings")
        .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .json, defaultFilename: "Lanternfold-progress") { result in
            switch result {
            case .success: message = "Progress exported."
            case .failure(let error):
                if (error as? CocoaError)?.code != .userCancelled {
                    message = "Export failed: \(error.localizedDescription)"
                }
            }
            exportDocument = nil
        }
        .confirmationDialog("Erase every saved puzzle, time and streak?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Erase all progress", role: .destructive) {
                do {
                    try context.delete(model: PuzzleRecord.self)
                    try context.save()
                    message = "All progress was erased."
                } catch {
                    message = "Progress could not be erased: \(error.localizedDescription)"
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone. Your purchase is not affected.")
        }
        .alert("Lanternfold", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }
}
