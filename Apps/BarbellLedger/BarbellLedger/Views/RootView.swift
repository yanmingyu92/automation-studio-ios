import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { DashboardView() }
                .tabItem { Label("Log", systemImage: "square.and.pencil") }
                .tag(0)
            NavigationStack { RoutineListView() }
                .tabItem { Label("Routines", systemImage: "list.bullet.clipboard") }
                .tag(1)
            NavigationStack { AnalyticsView() }
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(2)
            NavigationStack { ExerciseListView() }
                .tabItem { Label("Exercises", systemImage: "dumbbell.fill") }
                .tag(3)
            NavigationStack { SettingsView() }
                .tabItem { Label("More", systemImage: "ellipsis.circle") }
                .tag(4)
        }
        .tint(.accentColor)
        .task { DataController.seedExerciseCatalogIfNeeded(context: modelContext) }
    }
}
