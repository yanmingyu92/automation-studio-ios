import SwiftData
import SwiftUI

/// A string of lanterns under a night sky; decoration for the daily card and the purchase screen.
struct NightSky: View {
    var body: some View {
        Canvas { context, size in
            for index in 0..<34 {
                let seed = Double(index)
                let x = (sin(seed * 12.9898) * 0.5 + 0.5) * size.width
                let y = (sin(seed * 78.233) * 0.5 + 0.5) * size.height * 0.8
                let radius = 0.6 + seed.truncatingRemainder(dividingBy: 3) * 0.45
                context.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2)),
                    with: .color(.white.opacity(0.25 + seed.truncatingRemainder(dividingBy: 4) * 0.12))
                )
            }
            let sag = min(26, size.height * 0.16)
            var string = Path()
            string.move(to: CGPoint(x: -4, y: 8))
            string.addQuadCurve(to: CGPoint(x: size.width + 4, y: 8), control: CGPoint(x: size.width / 2, y: 8 + sag * 2))
            context.stroke(string, with: .color(.white.opacity(0.35)), lineWidth: 1)
            let count = 6
            for index in 0..<count {
                let t = (Double(index) + 0.5) / Double(count)
                let x = size.width * t
                let y = 8 + sag * 2 * 2 * t * (1 - t) + 9
                let glow = CGRect(x: x - 17, y: y - 14, width: 34, height: 34)
                context.fill(Path(ellipseIn: glow), with: .radialGradient(
                    Gradient(colors: [Palette.glow.opacity(0.75), Palette.glow.opacity(0)]),
                    center: CGPoint(x: glow.midX, y: glow.midY), startRadius: 1, endRadius: 17
                ))
                let body = CGRect(x: x - 6, y: y - 3, width: 12, height: 12)
                context.fill(Path(ellipseIn: body), with: .linearGradient(
                    Gradient(colors: [Palette.lanternCore, Palette.lanternBottom]),
                    startPoint: CGPoint(x: body.midX, y: body.minY), endPoint: CGPoint(x: body.midX, y: body.maxY)
                ))
                context.fill(Path(CGRect(x: x - 2.5, y: y - 5, width: 5, height: 2.5)), with: .color(Palette.lanternFrame))
            }
        }
        .background(LinearGradient(colors: [Palette.nightTop, Palette.nightBottom], startPoint: .top, endPoint: .bottom))
        .accessibilityHidden(true)
    }
}

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
            .first { $0.1.isUnlocked(isPro: store.isPro, today: today) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                dailyCard
                weekStrip
                if let resumable {
                    modeCard(
                        title: "Continue \(resumable.record.title)", systemImage: "arrow.uturn.forward",
                        detail: "\(resumable.record.size)×\(resumable.record.size) · \(Clock.text(resumable.record.elapsed)) so far",
                        tint: Palette.plot(3)
                    ) { navigator.play(resumable.source, isPro: store.isPro) }
                }
                modeCard(
                    title: "Journey", systemImage: "map.fill",
                    detail: "\(summary.solvedJourney) of \(JourneyPack.totalLevels) gardens lit",
                    tint: Palette.plot(0)
                ) { navigator.open(.journey) }
                modeCard(
                    title: "Daily archive", systemImage: "calendar",
                    detail: "Replay earlier days",
                    tint: Palette.plot(2)
                ) { navigator.open(.archive) }
                modeCard(
                    title: "Endless", systemImage: "infinity",
                    detail: store.isPro ? "Fresh gardens in any size" : "Fresh gardens in any size · Full Garden",
                    tint: Palette.plot(4)
                ) { navigator.open(.endless) }
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
            if phase == .active { refreshDay() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            refreshDay()
        }
        .task { refreshDay() }
    }

    private func refreshDay() {
        today = .today
        let solved = dailyRecord?.isComplete == true
        Task { await ReminderScheduler.refresh(todaySolved: solved) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Lanternfold")
                .font(.largeTitle.bold())
                .foregroundStyle(Palette.ink)
            Text("One lantern for every row, column and plot.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var dailyCard: some View {
        let request = dailySource.request
        let solved = dailyRecord?.isComplete == true
        return VStack(alignment: .leading, spacing: 10) {
            Spacer(minLength: 54)
            Text(dailySource.title)
                .font(.title.bold())
                .foregroundStyle(.white)
            Text("\(today.displayText) · \(request.size)×\(request.size) · \(request.difficulty?.title ?? "Mixed")")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))
            Button {
                navigator.play(dailySource, isPro: store.isPro)
            } label: {
                Label(dailyButtonTitle, systemImage: solved ? "checkmark.circle.fill" : "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .shadow(color: Color.accentColor.opacity(0.45), radius: 10, y: 5)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NightSky())
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var dailyButtonTitle: String {
        guard let record = dailyRecord else { return "Play today's garden" }
        if record.isComplete { return "Solved in \(Clock.text(record.elapsed))" }
        return record.isStarted ? "Continue · \(Clock.text(record.elapsed))" : "Play today's garden"
    }

    /// The last seven days; a lit lantern marks a daily garden solved on its own day.
    private var weekStrip: some View {
        let lit = Set(records.filter { $0.kind == "daily" && $0.completedOnDay }.compactMap(\.dayKey))
        let streak = summary.currentStreak
        let symbols = Calendar(identifier: .gregorian).veryShortWeekdaySymbols
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                Label(streak == 0 ? "Start a streak today" : (streak == 1 ? "1-day streak" : "\(streak)-day streak"), systemImage: "flame.fill")
                    .font(.headline)
                    .foregroundStyle(streak == 0 ? Palette.ink : Color.accentColor)
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { index in
                        let day = today.adding(days: index - 6)
                        let isLit = lit.contains(day.key)
                        VStack(spacing: 4) {
                            ZStack {
                                Circle()
                                    .fill(isLit ? Palette.glow.opacity(0.3) : Palette.ink.opacity(0.07))
                                if isLit {
                                    LanternGlyph(glowing: true)
                                }
                                if index == 6 {
                                    Circle().stroke(Color.accentColor, lineWidth: 2)
                                }
                            }
                            .frame(width: 36, height: 36)
                            Text(symbols[(day.weekday - 1) % 7])
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Daily streak: \(streak) \(streak == 1 ? "day" : "days"). Longest: \(summary.longestStreak).")
    }

    private func modeCard(title: String, systemImage: String, detail: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Card {
                HStack(spacing: 12) {
                    Image(systemName: systemImage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Palette.boardLine)
                        .frame(width: 44, height: 44)
                        .background(tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
