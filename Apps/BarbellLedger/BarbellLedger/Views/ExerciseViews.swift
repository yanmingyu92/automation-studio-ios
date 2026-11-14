import SwiftData
import SwiftUI

struct ExercisePickerSheet: View {
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var search = ""
    @State private var showingNewExercise = false
    @Environment(\.dismiss) private var dismiss
    let onSelect: (Exercise) -> Void

    private var filtered: [Exercise] {
        exercises.filter { !$0.isArchived && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.category.rawValue.localizedCaseInsensitiveContains(search)) }
    }

    var body: some View {
        NavigationStack {
            List {
                if filtered.isEmpty {
                    EmptyState(title: "No matching exercises", systemImage: "magnifyingglass", message: "Change your search or create a new exercise.")
                } else {
                    ForEach(filtered) { exercise in
                        Button {
                            onSelect(exercise)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(exercise.name).foregroundStyle(.primary)
                                    Text(exercise.category.rawValue).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "plus.circle")
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Exercise or category")
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button("New", systemImage: "plus") { showingNewExercise = true } }
            }
            .sheet(isPresented: $showingNewExercise) {
                ExerciseEditorView(exercise: nil) { created in
                    onSelect(created)
                }
            }
        }
    }
}

struct ExerciseListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var search = ""
    @State private var showingNew = false
    @State private var showArchived = false
    @State private var exerciseToDelete: Exercise?

    private var filtered: [Exercise] {
        exercises.filter { exercise in
            (showArchived || !exercise.isArchived) &&
            (search.isEmpty || exercise.name.localizedCaseInsensitiveContains(search) || exercise.category.rawValue.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        List {
            if filtered.isEmpty {
                EmptyState(title: search.isEmpty ? "No exercises" : "No matches", systemImage: "dumbbell", message: search.isEmpty ? "Create an exercise to start building routines and logging sets." : "Try a different name or category.")
            } else {
                ForEach(filtered) { exercise in
                    NavigationLink(destination: ExerciseDetailView(exercise: exercise)) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(exercise.name)
                                Text(exercise.category.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if exercise.isArchived {
                                Spacer()
                                Text("Archived").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button(exercise.isArchived ? "Unarchive" : "Archive") { exercise.isArchived.toggle(); try? modelContext.save() }
                            .tint(.orange)
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { exerciseToDelete = exercise }
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Search exercises")
        .navigationTitle("Exercises")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(showArchived ? "Hide Archived" : "Show Archived", systemImage: showArchived ? "archivebox.fill" : "archivebox") { showArchived.toggle() }
                    .accessibilityHint("Filters the exercise list by archived status")
            }
            ToolbarItem(placement: .primaryAction) { Button("New Exercise", systemImage: "plus") { showingNew = true } }
        }
        .sheet(isPresented: $showingNew) { ExerciseEditorView(exercise: nil) { _ in } }
        .confirmationDialog("Delete \(exerciseToDelete?.name ?? "exercise")?", isPresented: Binding(get: { exerciseToDelete != nil }, set: { if !$0 { exerciseToDelete = nil } }), titleVisibility: .visible) {
            Button("Delete Exercise", role: .destructive) {
                if let exerciseToDelete { modelContext.delete(exerciseToDelete); try? modelContext.save() }
                exerciseToDelete = nil
            }
            Button("Cancel", role: .cancel) { exerciseToDelete = nil }
        } message: { Text("Routine entries for it will be removed. Completed workouts keep their exercise names and sets.") }
    }
}

struct ExerciseEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var exercises: [Exercise]
    let exercise: Exercise?
    let onSave: (Exercise) -> Void
    @State private var name: String
    @State private var category: ExerciseCategory
    @State private var notes: String
    @State private var errorMessage: String?

    init(exercise: Exercise?, onSave: @escaping (Exercise) -> Void) {
        self.exercise = exercise
        self.onSave = onSave
        _name = State(initialValue: exercise?.name ?? "")
        _category = State(initialValue: exercise?.category ?? .other)
        _notes = State(initialValue: exercise?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Exercise") {
                    TextField("Name", text: $name)
                    Picker("Category", selection: $category) {
                        ForEach(ExerciseCategory.allCases) { Text($0.rawValue).tag($0) }
                    }
                    TextField("Technique notes (optional)", text: $notes, axis: .vertical)
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
            }
            .navigationTitle(exercise == nil ? "New Exercise" : "Edit Exercise")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { errorMessage = "Give the exercise a name."; return }
        guard !exercises.contains(where: { $0.id != exercise?.id && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            errorMessage = "An exercise with this name already exists."
            return
        }
        let result = exercise ?? Exercise(name: trimmed, category: category, notes: notes)
        result.name = trimmed
        result.category = category
        result.notes = notes
        if exercise == nil { modelContext.insert(result) }
        do {
            try modelContext.save()
            onSave(result)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

struct ExerciseDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(StoreManager.self) private var store
    @AppStorage("defaultWeightUnit") private var unit: WeightUnit = .kilograms
    @Query(sort: \Workout.startedAt, order: .reverse) private var workouts: [Workout]
    @Bindable var exercise: Exercise
    @State private var showingEditor = false
    @State private var showingPaywall = false

    private var history: [WorkoutExercise] {
        workouts.filter { $0.completedAt != nil }.flatMap(\.orderedExercises).filter {
            $0.matches(exercise)
        }
    }

    var body: some View {
        List {
            Section("Exercise") {
                LabeledContent("Category", value: exercise.category.rawValue)
                if !exercise.notes.isEmpty { Text(exercise.notes) }
                Toggle("Archived", isOn: $exercise.isArchived)
                    .accessibilityHint("Archived exercises stay in history but are hidden from pickers")
            }

            Section("Periodized progression") {
                if store.isPro {
                    if let rule = exercise.progressionRule {
                        ProgressionRuleEditor(rule: rule)
                    } else {
                        Text("Uses your completed sets, rep targets, RPE ceiling, and training-week block. Suggestions are always explained and optional.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("Set Up Progression") {
                            let rule = ProgressionRule(exercise: exercise)
                            rule.isEnabled = true
                            exercise.progressionRules?.append(rule)
                            try? modelContext.save()
                        }
                    }
                } else {
                    Button {
                        showingPaywall = true
                    } label: {
                        Label("BarbellLedger Pro progression", systemImage: "lock.fill")
                    }
                    Text("Basic logging stays free. Pro enables configurable weekly progression and deload suggestions.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Recent history") {
                if history.isEmpty {
                    Text("No completed sets yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(history.prefix(15)) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.workout?.startedAt.mediumDay ?? "Workout")
                                .font(.subheadline.weight(.semibold))
                            let sets = item.orderedSets.filter(\.isCompleted)
                            Text(sets.map { "\(unit.fromKilograms($0.weightKilograms).cleanString) \(unit.label) × \($0.reps)" }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .primaryAction) { Button("Edit") { showingEditor = true } } }
        .sheet(isPresented: $showingEditor) { ExerciseEditorView(exercise: exercise) { _ in } }
        .sheet(isPresented: $showingPaywall) { PaywallView() }
    }
}

struct ProgressionRuleEditor: View {
    @AppStorage("defaultWeightUnit") private var unit: WeightUnit = .kilograms
    @Bindable var rule: ProgressionRule

    var body: some View {
        Group {
            Toggle("Enable suggestions", isOn: $rule.isEnabled)
            if rule.isEnabled {
                Stepper("Rep range starts at \(rule.minimumReps)", value: $rule.minimumReps, in: 1...50)
                    .onChange(of: rule.minimumReps) { _, value in rule.maximumReps = max(value, rule.maximumReps) }
                Stepper("Rep range ends at \(rule.maximumReps)", value: $rule.maximumReps, in: 1...100)
                    .onChange(of: rule.maximumReps) { _, value in rule.minimumReps = min(value, rule.minimumReps) }
                VStack(alignment: .leading) {
                    Slider(value: $rule.rpeCeiling, in: 5...10, step: 0.5) {
                        Text("RPE ceiling")
                    }
                    .accessibilityValue("\(rule.rpeCeiling.cleanString) out of 10")
                    Text("Increase only when average RPE is \(rule.rpeCeiling.cleanString) or lower")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Stepper("Weekly increase: \(unit.fromKilograms(rule.weeklyIncrementKilograms).cleanString) \(unit.label)", value: weightBinding(\.weeklyIncrementKilograms), in: 0...(unit == .kilograms ? 20 : 45), step: unit == .kilograms ? 0.25 : 0.5)
                Stepper("Weight rounding: \(unit.fromKilograms(rule.roundingIncrementKilograms).cleanString) \(unit.label)", value: weightBinding(\.roundingIncrementKilograms), in: (unit == .kilograms ? 0.25 : 0.5)...(unit == .kilograms ? 20 : 45), step: unit == .kilograms ? 0.25 : 0.5)
                Picker("Deload schedule", selection: $rule.deloadEveryWeeks) {
                    Text("Off").tag(0)
                    ForEach([3, 4, 5, 6, 8, 12], id: \.self) { Text("Every \($0) training weeks").tag($0) }
                }
                if rule.deloadEveryWeeks > 0 {
                    Stepper("Deload reduction: \(Int(rule.deloadFraction * 100))%", value: $rule.deloadFraction, in: 0.05...0.3, step: 0.05)
                }
                Text("A weight increases after every working set reaches the top of the rep range without exceeding the RPE ceiling, at most once per training week. Otherwise it is held. A scheduled deload reduces the previous top set; later sessions in that deload week hold the reduced weight. All suggestions can be overridden.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func weightBinding(_ keyPath: ReferenceWritableKeyPath<ProgressionRule, Double>) -> Binding<Double> {
        Binding(
            get: { unit.fromKilograms(rule[keyPath: keyPath]) },
            set: { rule[keyPath: keyPath] = unit.toKilograms($0) }
        )
    }
}
