import SwiftData
import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(StoreManager.self) private var store
    @Environment(RestTimerManager.self) private var timer
    @AppStorage("defaultWeightUnit") private var unit: WeightUnit = .kilograms
    @AppStorage("defaultRestSeconds") private var defaultRestSeconds = 90
    @AppStorage("autoStartRest") private var autoStartRest = true
    @State private var showingPaywall = false
    @State private var confirmDeleteHistory = false
    @State private var errorMessage: String?

    private var proRowTitle: some View {
        Label(store.isPro ? "Pro is active" : "Unlock Pro", systemImage: store.isPro ? "checkmark.seal.fill" : "arrow.up.forward.circle.fill")
            .fixedSize(horizontal: true, vertical: false)
    }

    private var proRowDetail: some View {
        Text(store.isPro ? "Manage" : "View options")
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: true, vertical: false)
    }

    var body: some View {
        List {
            Section("BarbellLedger Pro") {
                Button { showingPaywall = true } label: {
                    // Stacks vertically when large text would otherwise break words mid-syllable.
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            proRowTitle
                            Spacer()
                            proRowDetail
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            proRowTitle
                            proRowDetail
                        }
                    }
                }
            }

            Section("Logging preferences") {
                Picker("Weight units", selection: $unit) {
                    ForEach(WeightUnit.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Stepper("Default rest: \(defaultRestSeconds.clockString)", value: $defaultRestSeconds, in: 15...900, step: 15)
                Toggle("Start rest after a completed set", isOn: $autoStartRest)
            }

            Section("Rest notifications") {
                LabeledContent("Permission", value: permissionLabel)
                if timer.authorizationStatus == .notDetermined {
                    Button("Enable Rest Notifications") {
                        Task { await requestNotifications() }
                    }
                } else if timer.authorizationStatus == .denied {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
                Text("Only rest-completion alerts are scheduled. They remain on this device and can be cancelled from the timer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Tools & data") {
                NavigationLink(destination: PlateCalculatorView()) { Label("Plate Calculator", systemImage: "scalemass") }
                NavigationLink(destination: ImportExportView()) { Label("FitNotes Import & CSV Export", systemImage: "doc.text") }
            }

            Section("About") {
                NavigationLink(destination: PrivacyView()) { Label("Privacy", systemImage: "hand.raised.fill") }
                NavigationLink(destination: LicensesView()) { Label("Licenses & Acknowledgements", systemImage: "doc.plaintext") }
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
            }

            Section("Data management") {
                Button("Delete All Workout History", role: .destructive) { confirmDeleteHistory = true }
                Text("Exercises, routines, and progression settings are kept. Imported and manually logged workouts are permanently deleted from this device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("More")
        .sheet(isPresented: $showingPaywall) { PaywallView() }
        .confirmationDialog("Delete all workout history?", isPresented: $confirmDeleteHistory, titleVisibility: .visible) {
            Button("Delete All Workouts", role: .destructive, action: deleteHistory)
            Button("Cancel", role: .cancel) {}
        } message: { Text("This cannot be undone. Export a CSV first if you want a backup.") }
        .alert("Data Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .task { await store.refreshEntitlements(); await timer.refreshPermission() }
    }

    private var permissionLabel: String {
        switch timer.authorizationStatus {
        case .authorized: "Allowed"
        case .denied: "Denied"
        case .notDetermined: "Not requested"
        case .provisional: "Provisional"
        case .ephemeral: "Ephemeral"
        @unknown default: "Unknown"
        }
    }

    private func requestNotifications() async {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            await timer.refreshPermission()
        } catch { errorMessage = error.localizedDescription }
    }

    private func deleteHistory() {
        do {
            let workouts = try modelContext.fetch(FetchDescriptor<Workout>())
            for workout in workouts { modelContext.delete(workout) }
            try modelContext.save()
            timer.stop()
        } catch { errorMessage = error.localizedDescription }
    }
}

struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PrivacySection(title: "Local first", text: "BarbellLedger stores exercises, routines, workouts, sets, and progression rules in an on-device SwiftData database. No account is required and there is no BarbellLedger workout-data server.")
                PrivacySection(title: "No tracking", text: "The app contains no advertising, third-party analytics, social SDK, or behavioral profiling. Workout data is not sold or shared for marketing.")
                PrivacySection(title: "Files you choose", text: "CSV import reads only the document you select through the system picker. CSV export writes only when you choose a destination. Imported data stays local unless you explicitly export it or your device backup includes app data.")
                PrivacySection(title: "Notifications", text: "Rest notifications contain a generic rest-complete message and are scheduled locally. Denying permission does not prevent logging or the in-app timer.")
                PrivacySection(title: "Purchases", text: "StoreKit contacts Apple to load products, process purchases, restore transactions, and verify current Pro entitlements. Apple handles payment information under its own terms and privacy policy. BarbellLedger does not receive your payment credentials.")
                PrivacySection(title: "Your control", text: "You can export completed history or permanently delete all workout history in More. Deleting exercises and routines preserves completed history as described in their confirmation dialogs.")
            }
            .padding()
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PrivacySection: View {
    let title: String
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(text).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct LicensesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("BarbellLedger is original native SwiftUI code with an original geometric app icon. It uses Apple-provided Swift, SwiftUI, SwiftData, Swift Charts, StoreKit, UserNotifications, UniformTypeIdentifiers, and Foundation frameworks.")
                Text("No third-party source code, application assets, analytics packages, or GPL/AGPL application code is bundled. There are no separate third-party license notices to display.")
                Text("FitNotes CSV compatibility is provided for user-directed data migration. BarbellLedger is independent and is not affiliated with or endorsed by FitNotes. FitNotes and other product names may be trademarks of their respective owners.")
                Text("Estimated one-rep max uses the published Epley equation. Progression suggestions are deterministic calculations from your configured rules and logged values, not medical or coaching advice.")
                Text("SF Symbols are used under Apple’s system-symbol license and remain subject to Apple’s platform guidelines.")
            }
            .foregroundStyle(.secondary)
            .padding()
        }
        .navigationTitle("Licenses")
        .navigationBarTitleDisplayMode(.inline)
    }
}
