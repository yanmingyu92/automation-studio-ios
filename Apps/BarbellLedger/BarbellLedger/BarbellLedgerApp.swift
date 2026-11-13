import SwiftData
import SwiftUI

@main
struct BarbellLedgerApp: App {
    private let container: ModelContainer?
    private let storageError: String?
    @State private var storeManager = StoreManager()
    @State private var restTimer = RestTimerManager()

    init() {
        do {
            container = try DataController.makeContainer()
            storageError = nil
        } catch {
            container = nil
            storageError = error.localizedDescription
        }
    }

    var body: some Scene {
        WindowGroup {
            if let container {
                RootView()
                    .modelContainer(container)
                    .environment(storeManager)
                    .environment(restTimer)
            } else {
                ContentUnavailableView {
                    Label("Storage Unavailable", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(storageError ?? "BarbellLedger could not open its local database. Your existing files have not been deleted.")
                }
            }
        }
    }
}
