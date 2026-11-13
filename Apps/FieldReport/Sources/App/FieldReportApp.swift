import SwiftData
import SwiftUI

@main
struct FieldReportApp: App {
    @StateObject private var store = StoreManager()
    @StateObject private var quota = ExportQuota()
    @StateObject private var transcription = TranscriptionManager()

    private let container: ModelContainer?
    private let persistenceError: String?

    init() {
        do {
            container = try ModelContainer(for: InspectionProject.self, Finding.self, FindingPhoto.self)
            persistenceError = nil
        } catch {
            container = nil
            persistenceError = error.localizedDescription
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let container {
                    ContentView()
                        .modelContainer(container)
                } else {
                    ContentUnavailableView(
                        "Local storage unavailable",
                        systemImage: "externaldrive.badge.exclamationmark",
                        description: Text("FieldReport could not open its project database. \(persistenceError ?? "Restart the app and try again.")")
                    )
                    .padding()
                }
            }
            .environmentObject(store)
            .environmentObject(quota)
            .environmentObject(transcription)
            .tint(.fieldTeal)
        }
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            ProjectListView()
                .tabItem { Label("Projects", systemImage: "folder.fill") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
    }
}
