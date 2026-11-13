import SwiftData
import SwiftUI

struct RoutineListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Routine.updatedAt, order: .reverse) private var routines: [Routine]
    @State private var showingNew = false

    var body: some View {
        List {
            if routines.isEmpty {
                EmptyState(title: "Build your first routine", systemImage: "list.bullet.clipboard", message: "Save exercises, set targets, and rest preferences so your next workout starts in a few taps.")
            } else {
                ForEach(routines) { routine in
                    NavigationLink(destination: RoutineDetailView(routine: routine)) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(routine.name).font(.headline)
                            Text(routine.orderedEntries.map(\.exerciseName).joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets { modelContext.delete(routines[index]) }
                    try? modelContext.save()
                }
            }
        }
        .navigationTitle("Routines")
        .toolbar { ToolbarItem(placement: .primaryAction) { Button("New Routine", systemImage: "plus") { showingNew = true } } }
        .sheet(isPresented: $showingNew) { NewRoutineView() }
    }
}

struct NewRoutineView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var notes = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Routine name", text: $name)
                TextField("Notes (optional)", text: $notes, axis: .vertical)
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            .navigationTitle("New Routine")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Create", action: create) }
            }
        }
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { errorMessage = "Give your routine a name."; return }
        let routine = Routine(name: trimmed, notes: notes)
        modelContext.insert(routine)
        do { try modelContext.save(); dismiss() } catch { errorMessage = error.localizedDescription }
    }
}

struct RoutineDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Workout.startedAt, order: .reverse) private var workouts: [Workout]
    @Bindable var routine: Routine
    @State private var showingPicker = false
    @State private var editingEntry: RoutineExercise?
    @State private var presentedWorkout: Workout?
    @State private var confirmDelete = false
    @State private var editMode: EditMode = .inactive
    @State private var errorMessage: String?

    private var activeWorkout: Workout? { workouts.first(where: \.isActive) }

    var body: some View {
        List {
            Section {
                TextField("Routine name", text: $routine.name)
                    .onChange(of: routine.name) { _, _ in routine.updatedAt = .now }
                TextField("Notes", text: $routine.notes, axis: .vertical)
            }
            Section("Exercises") {
                if routine.orderedEntries.isEmpty {
                    Text("Add exercises and target sets to make this routine ready to start.")
                        .foregroundStyle(.secondary)
                }
                ForEach(routine.orderedEntries) { entry in
                    Button { editingEntry = entry } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.exerciseName).foregroundStyle(.primary)
                                Text("\(entry.targetSets) sets × \(entry.targetReps) reps · rest \(entry.restSeconds.clockString)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "slider.horizontal.3").foregroundStyle(.secondary)
                        }
                    }
                }
                .onMove(perform: move)
                .onDelete(perform: deleteEntries)
                Button("Add exercise", systemImage: "plus") { showingPicker = true }
            }
            Section {
                Button(activeWorkout == nil ? "Start Workout" : "Resume Active Workout", systemImage: "play.fill") {
                    if let activeWorkout {
                        presentedWorkout = activeWorkout
                    } else {
                        do {
                            presentedWorkout = try DataController.createWorkout(from: routine, context: modelContext)
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
                .disabled(routine.orderedEntries.isEmpty && activeWorkout == nil)
            }
        }
        .environment(\.editMode, $editMode)
        .navigationTitle(routine.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
            ToolbarItem(placement: .topBarTrailing) { Button("Delete Routine", systemImage: "trash") { confirmDelete = true } }
        }
        .sheet(isPresented: $showingPicker) {
            ExercisePickerSheet { exercise in
                let entry = RoutineExercise(exercise: exercise, order: routine.orderedEntries.count)
                routine.entries?.append(entry)
                routine.updatedAt = .now
                try? modelContext.save()
                showingPicker = false
                editingEntry = entry
            }
        }
        .sheet(item: $editingEntry) { entry in RoutineEntryEditor(entry: entry) }
        .fullScreenCover(item: $presentedWorkout) { WorkoutSessionView(workout: $0) }
        .confirmationDialog("Delete this routine?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Routine", role: .destructive) {
                modelContext.delete(routine)
                try? modelContext.save()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("The template will be removed. Completed workouts are kept.") }
        .alert("Routine Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var entries = routine.orderedEntries
        entries.move(fromOffsets: source, toOffset: destination)
        DataController.reindex(entries)
        routine.updatedAt = .now
        try? modelContext.save()
    }

    private func deleteEntries(at offsets: IndexSet) {
        let entries = routine.orderedEntries
        for index in offsets {
            let entry = entries[index]
            routine.entries?.removeAll { $0.id == entry.id }
            modelContext.delete(entry)
        }
        DataController.reindex(routine.orderedEntries)
        try? modelContext.save()
    }
}

struct RoutineEntryEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var entry: RoutineExercise

    var body: some View {
        NavigationStack {
            Form {
                Section(entry.exerciseName) {
                    Stepper("Target sets: \(entry.targetSets)", value: $entry.targetSets, in: 1...20)
                    Stepper("Target reps: \(entry.targetReps)", value: $entry.targetReps, in: 1...100)
                    Stepper("Rest: \(entry.restSeconds.clockString)", value: $entry.restSeconds, in: 15...900, step: 15)
                }
                Section("RPE target") {
                    Toggle("Include RPE target", isOn: Binding(get: { entry.targetRPE != nil }, set: { entry.targetRPE = $0 ? 8 : nil }))
                    if entry.targetRPE != nil {
                        Slider(value: Binding(get: { entry.targetRPE ?? 8 }, set: { entry.targetRPE = $0 }), in: 4...10, step: 0.5)
                        Text("\((entry.targetRPE ?? 8).cleanString) RPE")
                    }
                }
            }
            .navigationTitle("Set Targets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
