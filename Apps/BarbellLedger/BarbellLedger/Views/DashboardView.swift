import SwiftData
import SwiftUI

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("defaultWeightUnit") private var unit: WeightUnit = .kilograms
    @Query(sort: \Workout.startedAt, order: .reverse) private var workouts: [Workout]
    @Query(sort: \Routine.updatedAt, order: .reverse) private var routines: [Routine]
    @State private var presentedWorkout: Workout?
    @State private var errorMessage: String?

    private var activeWorkout: Workout? { workouts.first(where: \.isActive) }
    private var completedWorkouts: [Workout] { workouts.filter { $0.completedAt != nil } }
    private var weekVolume: Double {
        guard let start = Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start else { return 0 }
        return completedWorkouts.filter { $0.startedAt >= start }.flatMap(\.completedSets).reduce(0) { $0 + $1.volumeKilograms }
    }

    var body: some View {
        List {
            if let activeWorkout {
                Section {
                    Button { presentedWorkout = activeWorkout } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "bolt.fill")
                                .font(.title2)
                                .foregroundStyle(.orange)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Workout in progress")
                                    .font(.headline)
                                Text("\(activeWorkout.displayName) · \(activeWorkout.completedSets.count.counted("set")) logged")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("Resume")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .accessibilityHint("Returns to your saved active workout")
                }
            } else {
                Section {
                    Button { startWorkout() } label: {
                        Label("Start an empty workout", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                    }
                    .listRowBackground(Color("AccentColor"))
                    .accessibilityHint("Creates a workout saved automatically on this device")
                }
            }

            Section("This week") {
                LazyVGrid(columns: metricColumns, spacing: 12) {
                    MetricCard(title: "Completed workouts", value: "\(completedThisWeek)", systemImage: "checkmark.circle.fill")
                    MetricCard(title: "Working volume", value: "\(unit.fromKilograms(weekVolume).cleanString) \(unit.label)", systemImage: "scalemass.fill", tint: .mint)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            if !routines.isEmpty {
                Section("Quick routines") {
                    ForEach(routines.prefix(3)) { routine in
                        Button { startWorkout(routine: routine) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(routine.name).font(.headline)
                                    Text(routine.orderedEntries.count.counted("exercise"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "play.fill")
                                    .accessibilityHidden(true)
                            }
                        }
                        .disabled(activeWorkout != nil)
                        .accessibilityHint(activeWorkout == nil ? "Starts a workout from this routine" : "Unavailable while another workout is in progress")
                    }
                }
            }

            Section("Recent workouts") {
                if completedWorkouts.isEmpty {
                    Text("Your completed workouts will appear here. Nothing is uploaded or shared.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(completedWorkouts.prefix(12)) { workout in
                        NavigationLink(destination: WorkoutDetailView(workout: workout)) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(workout.displayName).font(.headline)
                                Text(workout.startedAt.dayAndTime)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text("\(workout.completedSets.count.counted("set")) · \(unit.fromKilograms(workout.completedSets.reduce(0) { $0 + $1.volumeKilograms }).cleanString) \(unit.label) volume")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete(perform: deleteWorkouts)
                }
            }
        }
        .safeAreaPadding(.bottom, dynamicTypeSize.isAccessibilitySize ? 32 : 0)
        .navigationTitle("BarbellLedger")
        .alert("Couldn’t save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .fullScreenCover(item: $presentedWorkout) { workout in
            WorkoutSessionView(workout: workout)
        }
    }

    private var metricColumns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible())]
    }

    private var completedThisWeek: Int {
        guard let start = Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start else { return 0 }
        return completedWorkouts.filter { $0.startedAt >= start }.count
    }

    private func startWorkout(routine: Routine? = nil) {
        guard activeWorkout == nil else {
            presentedWorkout = activeWorkout
            return
        }
        do {
            presentedWorkout = try DataController.createWorkout(from: routine, context: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteWorkouts(at offsets: IndexSet) {
        for index in offsets { modelContext.delete(completedWorkouts[index]) }
        do { try modelContext.save() } catch { errorMessage = error.localizedDescription }
    }
}

struct WorkoutDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("defaultWeightUnit") private var unit: WeightUnit = .kilograms
    @Bindable var workout: Workout
    @State private var confirmDelete = false

    var body: some View {
        List {
            Section {
                TextField("Workout name", text: $workout.name)
                TextField("Notes", text: $workout.notes, axis: .vertical)
                LabeledContent("Started", value: workout.startedAt.dayAndTime)
                if let completedAt = workout.completedAt {
                    LabeledContent("Completed", value: completedAt.dayAndTime)
                }
                LabeledContent("Duration", value: workout.duration.clockString)
            }
            ForEach(workout.orderedExercises) { item in
                Section(item.exerciseName) {
                    if !item.notes.isEmpty { Text(item.notes).foregroundStyle(.secondary) }
                    ForEach(item.orderedSets.filter(\.isCompleted)) { set in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(set.kind.label)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(set.kind.color)
                                Spacer()
                                Text("\(unit.fromKilograms(set.weightKilograms).cleanString) \(unit.label) × \(set.reps)")
                                if let rpe = set.rpe { Text("@ \(rpe.cleanString)").foregroundStyle(.secondary) }
                            }
                            if !set.personalRecordLabels.isEmpty {
                                ForEach(set.personalRecordLabels, id: \.self) { PRLabel(text: $0) }
                            }
                            if !set.note.isEmpty { Text(set.note).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
        }
        .navigationTitle(workout.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
            }
        }
        .confirmationDialog("Delete this workout?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Workout", role: .destructive) {
                modelContext.delete(workout)
                try? modelContext.save()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Its exercises and sets will be permanently removed. This cannot be undone.") }
    }
}
