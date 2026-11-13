import SwiftData
import SwiftUI

@main
struct DocKeeperApp: App {
    @StateObject private var storeManager = StoreManager()
    @StateObject private var notificationManager = NotificationManager()

    private let modelContainer: ModelContainer?
    private let modelContainerError: String?

    init() {
        do {
            modelContainer = try ModelContainer(for: DocumentRecord.self)
            modelContainerError = nil
        } catch {
            modelContainer = nil
            modelContainerError = error.localizedDescription
        }
    }

    var body: some Scene {
        WindowGroup {
            if let modelContainer {
                RootView()
                    .environmentObject(storeManager)
                    .environmentObject(notificationManager)
                    .modelContainer(modelContainer)
            } else {
                ContentUnavailableView {
                    Label("Local Storage Unavailable", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(modelContainerError ?? "DocKeeper could not open its local document database.")
                } actions: {
                    Text("Your files have not been uploaded anywhere. Reopen the app or check available device storage.")
                        .font(.footnote)
                }
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var notifications: NotificationManager

    var body: some View {
        TabView {
            DocumentsView()
                .tabItem { Label("Documents", systemImage: "doc.text.magnifyingglass") }
            DashboardView()
                .tabItem { Label("Expirations", systemImage: "calendar.badge.clock") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(Color("AccentColor"))
        .task { await notifications.refreshAuthorization() }
    }
}
