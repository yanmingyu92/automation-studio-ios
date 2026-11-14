import Charts
import SwiftData
import SwiftUI

struct AnalyticsView: View {
    @Environment(StoreManager.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("defaultWeightUnit") private var unit: WeightUnit = .kilograms
    @Query(sort: \Workout.startedAt, order: .reverse) private var workouts: [Workout]
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var showingPaywall = false
    @State private var selectedExercise: Exercise?

    private var completed: [Workout] { workouts.filter { $0.completedAt != nil } }
    private var recordEvents: [PersonalRecordEvent] { AnalyticsService.personalRecordEvents(workouts: completed) }

    var body: some View {
        List {
            Section("Overview") {
                LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    MetricCard(title: "All-time workouts", value: "\(completed.count)", systemImage: "calendar.badge.checkmark")
                    MetricCard(title: "Detected records", value: "\(recordEvents.reduce(0) { $0 + $1.labels.count })", systemImage: "trophy.fill", tint: .orange)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            if completed.isEmpty {
                EmptyState(title: "Your progress starts with a set", systemImage: "chart.line.uptrend.xyaxis", message: "Finish a workout or import your FitNotes history. Charts are calculated on this device from your actual sets.")
            } else if store.isPro {
                volumeSection
                oneRepMaxSection
                recordsSection
            } else {
                Section {
                    LockedFeature(title: "See the full picture", message: "Pro unlocks volume trends, estimated one-rep max charts, and personal-record analytics. Basic workout logging and PR detection are free.") { showingPaywall = true }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
        }
        .navigationTitle("Progress")
        .sheet(isPresented: $showingPaywall) { PaywallView() }
        .onAppear { selectDefaultExercise() }
        .onChange(of: exercises.count) { _, _ in selectDefaultExercise() }
    }

    @ViewBuilder
    private var volumeSection: some View {
        let points = AnalyticsService.volumeByWeek(workouts: completed)
        Section("Working volume · 12 weeks") {
            Chart(points) { point in
                BarMark(
                    x: .value("Week", point.date, unit: .weekOfYear),
                    y: .value("Volume", unit.fromKilograms(point.volumeKilograms))
                )
                .foregroundStyle(.mint.gradient)
                .cornerRadius(4)
                .accessibilityLabel(point.date.mediumDay)
                .accessibilityValue("\(unit.fromKilograms(point.volumeKilograms).cleanString) \(unit.label)")
            }
            .frame(height: 230)
            .chartYAxisLabel(unit.label)
            .accessibilityLabel("Weekly working volume chart")
            Text("Volume is weight × reps for completed working, drop, and failure sets. Warm-ups are excluded. Empty weeks remain visible.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var oneRepMaxSection: some View {
        Section("Estimated one-rep max") {
            Picker("Exercise", selection: $selectedExercise) {
                Text("Choose an exercise").tag(Exercise?.none)
                ForEach(exercises.filter { !$0.isArchived || $0.id == selectedExercise?.id }) { exercise in
                    Text(exercise.name).tag(Exercise?.some(exercise))
                }
            }
            let points = AnalyticsService.oneRepMaxPoints(workouts: completed, exercise: selectedExercise)
            if points.isEmpty {
                Text("Complete a weighted set for this exercise to plot its estimated one-rep max.")
                    .foregroundStyle(.secondary)
            } else {
                Chart(points) { point in
                    LineMark(x: .value("Workout", point.date), y: .value("Estimated 1RM", unit.fromKilograms(point.valueKilograms)))
                        .foregroundStyle(.orange)
                        .interpolationMethod(.catmullRom)
                    PointMark(x: .value("Workout", point.date), y: .value("Estimated 1RM", unit.fromKilograms(point.valueKilograms)))
                        .foregroundStyle(.orange)
                        .accessibilityLabel(point.date.mediumDay)
                        .accessibilityValue("\(unit.fromKilograms(point.valueKilograms).cleanString) \(unit.label)")
                }
                .frame(height: 230)
                .chartYAxisLabel(unit.label)
                .accessibilityLabel("Estimated one-rep max trend for \(selectedExercise?.name ?? "exercise")")
                if let latest = points.last {
                    Text("Latest best-set estimate: \(unit.fromKilograms(latest.valueKilograms).cleanString) \(unit.label)")
                        .font(.subheadline.weight(.semibold))
                }
            }
            Text("Uses the Epley estimate: weight × (1 + reps ÷ 30), based on each workout’s best set. It is a logging metric, not a coaching or health assessment.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var recordsSection: some View {
        Section("Personal records · 6 months") {
            let points = AnalyticsService.prCountsByMonth(events: recordEvents)
            Chart(points) { point in
                BarMark(x: .value("Month", point.date, unit: .month), y: .value("Records", point.count))
                    .foregroundStyle(.orange.gradient)
                    .cornerRadius(4)
                    .accessibilityLabel(point.date.formatted(.dateTime.month()))
                    .accessibilityValue(point.count.counted("record"))
            }
            .frame(height: 200)
            .chartYAxis { AxisMarks(values: .stride(by: 1)) }
            .accessibilityLabel("Personal records by month chart")
            Text("A record is counted when a completed set exceeds earlier weight, estimated 1RM, or reps at the same weight. First logged weight and estimated 1RM establish a baseline.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(recordEvents.prefix(8)) { event in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(event.exerciseName).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(event.date.mediumDay).font(.caption).foregroundStyle(.secondary)
                    }
                    Text("\(unit.fromKilograms(event.weightKilograms).cleanString) \(unit.label) × \(event.reps) · \(event.labels.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func selectDefaultExercise() {
        guard selectedExercise == nil || !exercises.contains(where: { $0.id == selectedExercise?.id }) else { return }
        selectedExercise = exercises.first { exercise in
            !AnalyticsService.oneRepMaxPoints(workouts: completed, exercise: exercise).isEmpty
        } ?? exercises.first
    }
}
