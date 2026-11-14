import SwiftData
import SwiftUI

/// One sheet presentation of the set editor. Carrying `completing` in the item itself keeps the sheet
/// content from reading a stale flag captured before the state update.
private struct SetEditRequest: Identifiable {
    let workoutSet: WorkoutSet
    let completing: Bool
    var id: UUID { workoutSet.id }
}

struct WorkoutSessionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(RestTimerManager.self) private var timer
    @Environment(StoreManager.self) private var store
    @AppStorage("defaultRestSeconds") private var defaultRestSeconds = 90
    @AppStorage("autoStartRest") private var autoStartRest = true
    @Query(sort: \Workout.startedAt, order: .reverse) private var workouts: [Workout]
    @Bindable var workout: Workout

    @State private var editRequest: SetEditRequest?
    @State private var showingExercisePicker = false
    @State private var showingRestTimer = false
    @State private var showingPaywall = false
    @State private var confirmFinish = false
    @State private var confirmDiscard = false
    @State private var recordMessage: String?
    @State private var errorMessage: String?
    @State private var exercisePendingRemoval: WorkoutExercise?

    /// Set before the model is deleted so the body stops reading it; SwiftData traps on access to a deleted, saved model.
    @State private var isDiscarded = false

    var body: some View {
        if isDiscarded { Color.clear } else { content }
    }

    @ViewBuilder private var content: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Workout name", text: $workout.name)
                    TextField("Session notes", text: $workout.notes, axis: .vertical)
                        .accessibilityLabel("Workout notes")
                    RestTimerBanner { showingRestTimer = true }
                }

                if let recordMessage {
                    Section {
                        Label(recordMessage, systemImage: "trophy.fill")
                            .foregroundStyle(.orange)
                            .font(.headline)
                    }
                }

                ForEach(workout.orderedExercises) { item in
                    WorkoutExerciseCard(
                        item: item,
                        workout: workout,
                        workouts: workouts,
                        previous: ProgressionEngine.previousExercise(before: workout, matching: item, in: workouts),
                        isPro: store.isPro,
                        onEditSet: { editRequest = SetEditRequest(workoutSet: $0, completing: false) },
                        onToggleSet: { toggle($0, in: item) },
                        onAddSet: { addSet(to: item) },
                        onDeleteSet: { delete($0, from: item) },
                        onMoveSet: { move($0, direction: $1, in: item) },
                        onApplySuggestion: { apply($0, to: item) },
                        onUnlock: { showingPaywall = true },
                        canMoveEarlier: item.order > 0,
                        canMoveLater: item.order < (workout.exercises?.count ?? 0) - 1,
                        onMoveExercise: { moveExercise(item, direction: $0) },
                        onRemoveExercise: { exercisePendingRemoval = item }
                    )
                }

                Section {
                    Button { showingExercisePicker = true } label: {
                        Label("Add exercise", systemImage: "plus")
                    }
                }

                Section {
                    Button { confirmFinish = true } label: {
                        Text("Finish Workout").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    Button("Discard Workout", role: .destructive) { confirmDiscard = true }
                        .frame(maxWidth: .infinity)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle(workout.startedAt.mediumDay)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Minimize", systemImage: "chevron.down") { save(); dismiss() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Rest timer", systemImage: "timer") { showingRestTimer = true }
                }
            }
            .sheet(item: $editRequest) { request in
                let set = request.workoutSet
                let completing = request.completing
                SetEditorView(set: set, markCompleted: completing) { edited in
                    if edited.isCompleted {
                        updateRecords(for: edited)
                        if completing, autoStartRest, let item = edited.workoutExercise {
                            Task { await timer.start(seconds: TimeInterval(item.restSeconds)) }
                        }
                    }
                    save()
                }
            }
            .sheet(isPresented: $showingExercisePicker) {
                ExercisePickerSheet { exercise in
                    addExercise(exercise)
                    showingExercisePicker = false
                }
            }
            .sheet(isPresented: $showingRestTimer) { RestTimerView() }
            .sheet(isPresented: $showingPaywall) { PaywallView() }
            .confirmationDialog("Finish this workout?", isPresented: $confirmFinish, titleVisibility: .visible) {
                Button("Finish Workout") { finish() }
                Button("Keep Logging", role: .cancel) {}
            } message: { Text("Completed sets will be saved to your history. Incomplete planned sets will be removed; choose Keep Logging or Minimize if you want to retain them.") }
            .confirmationDialog("Discard this active workout?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard Workout", role: .destructive) { discard() }
                Button("Cancel", role: .cancel) {}
            } message: { Text("All sets in this active workout will be permanently deleted.") }
            .alert("Workout Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
            .confirmationDialog(
                "Remove \(exercisePendingRemoval?.exerciseName ?? "exercise")?",
                isPresented: Binding(get: { exercisePendingRemoval != nil }, set: { if !$0 { exercisePendingRemoval = nil } }),
                titleVisibility: .visible
            ) {
                Button("Remove Exercise", role: .destructive) {
                    if let item = exercisePendingRemoval { removeExercise(item) }
                    exercisePendingRemoval = nil
                }
                Button("Cancel", role: .cancel) { exercisePendingRemoval = nil }
            } message: { Text("Its sets in this workout will be permanently deleted.") }
        }
    }

    private func toggle(_ set: WorkoutSet, in item: WorkoutExercise) {
        // An empty set cannot be completed directly: it would be saved to history as "0 × 0"
        // and let the workout finish with no real data. Ask for values first.
        if !set.isCompleted, set.weightKilograms <= 0, set.reps <= 0, set.distanceMeters <= 0, set.durationSeconds <= 0 {
            editRequest = SetEditRequest(workoutSet: set, completing: true)
            return
        }
        set.isCompleted.toggle()
        set.completedAt = set.isCompleted ? .now : nil
        if set.isCompleted {
            updateRecords(for: set, item: item)
            if autoStartRest { Task { await timer.start(seconds: TimeInterval(item.restSeconds)) } }
        } else {
            set.personalRecordLabels = []
        }
        save()
    }

    private func updateRecords(for set: WorkoutSet, item explicitItem: WorkoutExercise? = nil) {
        guard let item = explicitItem ?? set.workoutExercise else { return }
        let records = PersonalRecordDetector.detect(for: set, item: item, workout: workout, workouts: workouts)
        set.personalRecordLabels = records.map(\.label)
        if !records.isEmpty { recordMessage = records.map(\.label).joined(separator: " · ") }
    }

    private func addSet(to item: WorkoutExercise) {
        let last = item.orderedSets.last
        let set = WorkoutSet(order: item.orderedSets.count)
        if let last {
            set.weightKilograms = last.weightKilograms
            set.reps = last.reps
            set.rpe = last.rpe
            set.kind = last.kind == .warmup ? .working : last.kind
        }
        item.sets?.append(set)
        save()
    }

    private func addExercise(_ exercise: Exercise) {
        guard !workout.orderedExercises.contains(where: { $0.matches(exercise) }) else {
            errorMessage = "That exercise is already in this workout. Add another set instead."
            return
        }
        let item = WorkoutExercise(exercise: exercise, order: workout.orderedExercises.count)
        item.restSeconds = defaultRestSeconds
        item.sets?.append(WorkoutSet(order: 0))
        workout.exercises?.append(item)
        save()
    }

    private func delete(_ set: WorkoutSet, from item: WorkoutExercise) {
        item.sets?.removeAll { $0.id == set.id }
        modelContext.delete(set)
        for (index, remaining) in item.orderedSets.enumerated() { remaining.order = index }
        save()
    }

    private func move(_ set: WorkoutSet, direction: Int, in item: WorkoutExercise) {
        var sets = item.orderedSets
        guard let index = sets.firstIndex(where: { $0.id == set.id }) else { return }
        let destination = index + direction
        guard sets.indices.contains(destination) else { return }
        sets.swapAt(index, destination)
        for (index, set) in sets.enumerated() { set.order = index }
        save()
    }

    private func moveExercise(_ item: WorkoutExercise, direction: Int) {
        var items = workout.orderedExercises
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let target = index + direction
        guard items.indices.contains(target) else { return }
        items.swapAt(index, target)
        DataController.reindex(items)
        save()
    }

    private func removeExercise(_ item: WorkoutExercise) {
        workout.exercises?.removeAll { $0.id == item.id }
        modelContext.delete(item)
        DataController.reindex(workout.orderedExercises)
        save()
    }

    private func apply(_ suggestion: ProgressionSuggestion, to item: WorkoutExercise) {
        let target = item.orderedSets.first { !$0.isCompleted && $0.kind != .warmup } ?? WorkoutSet(order: item.orderedSets.count)
        if !item.orderedSets.contains(where: { $0.id == target.id }) { item.sets?.append(target) }
        target.weightKilograms = suggestion.weightKilograms
        target.reps = suggestion.targetReps
        save()
    }

    private func finish() {
        guard !workout.completedSets.isEmpty else {
            errorMessage = "Complete at least one set before finishing. You can also minimize to continue later or discard the workout."
            return
        }
        for item in workout.orderedExercises {
            for set in item.orderedSets where !set.isCompleted {
                item.sets?.removeAll { $0.id == set.id }
                modelContext.delete(set)
            }
            if item.orderedSets.isEmpty {
                workout.exercises?.removeAll { $0.id == item.id }
                modelContext.delete(item)
            }
        }
        DataController.reindex(workout.orderedExercises)
        workout.completedAt = .now
        if workout.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { workout.name = "Workout" }
        timer.stop()
        if save() { dismiss() }
    }

    private func discard() {
        timer.stop()
        isDiscarded = true
        modelContext.delete(workout)
        if save() { dismiss() } else { isDiscarded = false }
    }

    @discardableResult
    private func save() -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

struct WorkoutExerciseCard: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("defaultWeightUnit") private var unit: WeightUnit = .kilograms
    @Bindable var item: WorkoutExercise
    let workout: Workout
    let workouts: [Workout]
    let previous: WorkoutExercise?
    let isPro: Bool
    let onEditSet: (WorkoutSet) -> Void
    let onToggleSet: (WorkoutSet) -> Void
    let onAddSet: () -> Void
    let onDeleteSet: (WorkoutSet) -> Void
    let onMoveSet: (WorkoutSet, Int) -> Void
    let onApplySuggestion: (ProgressionSuggestion) -> Void
    let onUnlock: () -> Void
    let canMoveEarlier: Bool
    let canMoveLater: Bool
    let onMoveExercise: (Int) -> Void
    let onRemoveExercise: () -> Void

    private var suggestion: ProgressionSuggestion? {
        ProgressionEngine.suggestion(for: item, in: workout, workouts: workouts)
    }

    var body: some View {
        Section {
            TextField("Exercise notes", text: $item.notes, axis: .vertical)
                .font(.subheadline)

            if let previous {
                let previousSets = previous.orderedSets.filter { $0.isCompleted && $0.kind != .warmup }
                VStack(alignment: .leading, spacing: 4) {
                    Label("Last time · \(previous.workout?.startedAt.mediumDay ?? "Previous session")", systemImage: "clock.arrow.circlepath")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(previousSets.map { "\(unit.fromKilograms($0.weightKilograms).cleanString) \(unit.label) × \($0.reps)" }.joined(separator: "  ·  "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }

            if item.exercise?.progressionRule?.isEnabled == true {
                if isPro, let suggestion {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(suggestion.isDeload ? "Suggested deload" : "Progression suggestion", systemImage: suggestion.isDeload ? "arrow.down.right.circle" : "arrow.up.right.circle")
                            .font(.subheadline.weight(.semibold))
                        Text("\(unit.fromKilograms(suggestion.weightKilograms).cleanString) \(unit.label) × \(suggestion.targetReps)")
                            .font(.headline)
                        Text(suggestion.reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Apply to next open set") { onApplySuggestion(suggestion) }
                            .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 4)
                } else if !isPro {
                    Button("Unlock your configured progression suggestion", action: onUnlock)
                        .font(.subheadline)
                } else {
                    Text("Complete a working session for this exercise to receive a rule-based suggestion.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(item.orderedSets) { set in
                HStack(spacing: 10) {
                    Button { onEditSet(set) } label: {
                        HStack(spacing: 10) {
                            Text(set.kind.shortLabel)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(set.kind.color)
                                .frame(minWidth: 26)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(unit.fromKilograms(set.weightKilograms).cleanString) \(unit.label) × \(set.reps)")
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.primary)
                                HStack {
                                    if let rpe = set.rpe { Text("RPE \(rpe.cleanString)") }
                                    if !set.personalRecordLabels.isEmpty { Text("PR").foregroundStyle(.orange) }
                                    if !set.note.isEmpty { Text(set.note).lineLimit(1) }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit set \(set.order + 1), \(set.kind.label), \(unit.fromKilograms(set.weightKilograms).cleanString) \(unit.label), \(set.reps.counted("repetition")), \(set.isCompleted ? "completed" : "not completed")")
                    Button {
                        onToggleSet(set)
                    } label: {
                        Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundStyle(set.isCompleted ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(set.isCompleted ? "Mark set \(set.order + 1) incomplete" : "Complete set \(set.order + 1)")
                }
                .contextMenu {
                    Button("Move earlier", systemImage: "arrow.up") { onMoveSet(set, -1) }
                        .disabled(set.order == 0)
                    Button("Move later", systemImage: "arrow.down") { onMoveSet(set, 1) }
                        .disabled(set.order == item.orderedSets.count - 1)
                    Button("Delete", systemImage: "trash", role: .destructive) { onDeleteSet(set) }
                }
                .swipeActions {
                    Button("Delete", role: .destructive) { onDeleteSet(set) }
                }
            }

            Button("Add set", systemImage: "plus", action: onAddSet)
        } header: {
            HStack {
                Text(item.exerciseName)
                Spacer()
                Text("\(item.orderedSets.filter(\.isCompleted).count)/\(item.orderedSets.count)")
                    .font(.caption)
                    .accessibilityLabel("\(item.orderedSets.filter(\.isCompleted).count) of \(item.orderedSets.count.counted("set")) completed")
                Menu {
                    Button("Move Earlier", systemImage: "arrow.up") { onMoveExercise(-1) }
                        .disabled(!canMoveEarlier)
                    Button("Move Later", systemImage: "arrow.down") { onMoveExercise(1) }
                        .disabled(!canMoveLater)
                    Button("Remove Exercise", systemImage: "trash", role: .destructive, action: onRemoveExercise)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.body)
                        .frame(minWidth: 44, minHeight: 32, alignment: .trailing)
                }
                .accessibilityLabel("Options for \(item.exerciseName)")
                .textCase(nil)
            }
        }
    }
}
