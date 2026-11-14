import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(Navigator.self) private var navigator
    @Environment(StoreManager.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Query private var records: [PuzzleRecord]
    @State private var today = DayStamp.today

    private var summary: ProgressSummary { ProgressSummary(records: records, today: today) }
    private var dailySource: PuzzleSource { .daily(today) }
    private var dailyRecord: PuzzleRecord? { records.first { $0.key == dailySource.key } }

    private var resumable: (record: PuzzleRecord, source: PuzzleSource)? {
        records
            .filter { !$0.isComplete && $0.isStarted && $0.key != dailySource.key }
            .sorted { $0.updatedAt > $1.updatedAt }
            .lazy
            .compactMap { record in PuzzleSource(record: record).map { (record, $0) } }
            .first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                dailyCard
                if let resumable {
                    resumeCard(resumable.record, source: resumable.source)
                }
                modeCard(
                    title: "Journey", systemImage: "map",
                    detail: "\(summary.solvedJourney) of \(JourneyPack.totalLevels) gardens lit",
                    route: .journey
                )
                modeCard(
                    title: "Daily archive", systemImage: "calendar",
                    detail: "Replay earlier days",
                    route: .archive
                )
                modeCard(
                    title: "Endless", systemImage: "infinity",
                    detail: store.isPro ? "Fresh gardens in any size" : "Fresh gardens in any size · Full Garden",
                    route: .endless
                )
            }
            .padding(16)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.background.ignoresSafeArea())
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("How to play", systemImage: "questionmark.circle") { navigator.showingRules = true }
                Button("Statistics", systemImage: "chart.bar") { navigator.open(.stats) }
                Button("Settings", systemImage: "gearshape") { navigator.open(.settings) }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { today = .today }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            today = .today
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            LanternGlyph(glowing: true)
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text("Lanternfold")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Palette.ink)
                Text("One lantern for every row, column and plot.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var dailyCard: some View {
        let request = dailySource.request
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(dailySource.title)
                        .font(.title2.bold())
                    Spacer()
                    Pill(text: summary.currentStreak == 1 ? "1 day" : "\(summary.currentStreak) days", systemImage: "flame.fill")
                        .accessibilityLabel("Current streak: \(summary.currentStreak) \(summary.currentStreak == 1 ? "day" : "days")")
                }
                Text("\(today.displayText) · \(request.size)×\(request.size) · \(request.difficulty?.title ?? "Mixed")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    navigator.play(dailySource, isPro: store.isPro)
                } label: {
                    Label(dailyButtonTitle, systemImage: dailyRecord?.isComplete == true ? "checkmark.circle.fill" : "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var dailyButtonTitle: String {
        guard let record = dailyRecord else { return "Play today's garden" }
        if record.isComplete { return "Solved in \(Clock.text(record.elapsed))" }
        return record.isStarted ? "Continue · \(Clock.text(record.elapsed))" : "Play today's garden"
    }

    private func resumeCard(_ record: PuzzleRecord, source: PuzzleSource) -> some View {
        Button {
            navigator.play(source, isPro: store.isPro)
        } label: {
            Card {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.uturn.forward.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Continue \(record.title)")
                            .font(.headline)
                            .foregroundStyle(Palette.ink)
                        Text("\(record.size)×\(record.size) · \(Clock.text(record.elapsed)) so far")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func modeCard(title: String, systemImage: String, detail: String, route: Route) -> some View {
        Button {
            navigator.open(route)
        } label: {
            Card {
                HStack(spacing: 12) {
                    Image(systemName: systemImage)
                        .font(.title2)
                        .frame(width: 36)
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(Palette.ink)
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
