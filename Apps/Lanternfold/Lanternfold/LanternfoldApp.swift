import SwiftData
import SwiftUI

enum Route: Hashable {
    case game(PuzzleSource)
    case journey
    case pack(Int)
    case archive
    case endless
    case stats
    case settings
}

@MainActor
@Observable
final class Navigator {
    var path: [Route] = []
    var showingPaywall = false
    var showingRules = false

    func open(_ route: Route) {
        path.append(route)
    }

    /// Opens a puzzle, or the paywall when the puzzle belongs to the Full Garden.
    func play(_ source: PuzzleSource, isPro: Bool, replacingCurrent: Bool = false) {
        guard source.isUnlocked(isPro: isPro) else {
            showingPaywall = true
            return
        }
        if replacingCurrent, !path.isEmpty {
            path[path.count - 1] = .game(source)
        } else {
            path.append(.game(source))
        }
    }
}

@main
struct LanternfoldApp: App {
    @State private var store = StoreManager()
    @State private var navigator = Navigator()
    private let container: Result<ModelContainer, Error>

    init() {
        container = Result { try ModelContainer(for: PuzzleRecord.self) }
    }

    var body: some Scene {
        WindowGroup {
            switch container {
            case .success(let container):
                RootView()
                    .environment(store)
                    .environment(navigator)
                    .modelContainer(container)
                    .fontDesign(.rounded)
                    .tint(Color.accentColor)
            case .failure(let error):
                ContentUnavailableView(
                    "Saved puzzles could not be opened",
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text("Free some storage space and reopen Lanternfold. \(error.localizedDescription)")
                )
            }
        }
    }
}

struct RootView: View {
    @Environment(Navigator.self) private var navigator
    @AppStorage(SettingKey.seenRules) private var seenRules = false

    var body: some View {
        @Bindable var navigator = navigator
        NavigationStack(path: $navigator.path) {
            HomeView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .game(let source): GameView(source: source).id(source)
                    case .journey: JourneyView()
                    case .pack(let index): PackView(packIndex: index)
                    case .archive: ArchiveView()
                    case .endless: EndlessView()
                    case .stats: StatsView()
                    case .settings: SettingsView()
                    }
                }
        }
        .sheet(isPresented: $navigator.showingPaywall) {
            PaywallView()
        }
        .sheet(isPresented: $navigator.showingRules) {
            RulesView()
        }
        .onAppear {
            if !seenRules {
                seenRules = true
                navigator.showingRules = true
            }
        }
    }
}
