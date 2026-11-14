import Foundation
import SwiftData

@MainActor
struct DataController {
    static func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Exercise.self,
            Routine.self,
            RoutineExercise.self,
            Workout.self,
            WorkoutExercise.self,
            WorkoutSet.self,
            ProgressionRule.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    static func seedExerciseCatalogIfNeeded(context: ModelContext) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "barbellledger.catalog.seeded.v1") else { return }
        let descriptor = FetchDescriptor<Exercise>()
        let existing = (try? context.fetchCount(descriptor)) ?? 0
        if existing == 0 {
            let catalog: [(String, ExerciseCategory)] = [
                ("Back Squat", .legs),
                ("Front Squat", .legs),
                ("Deadlift", .back),
                ("Romanian Deadlift", .legs),
                ("Bench Press", .chest),
                ("Overhead Press", .shoulders),
                ("Barbell Row", .back),
                ("Pull-Up", .back),
                ("Lat Pulldown", .back),
                ("Incline Dumbbell Press", .chest),
                ("Dumbbell Curl", .arms),
                ("Triceps Pressdown", .arms),
                ("Leg Press", .legs),
                ("Calf Raise", .legs),
                ("Plank", .core)
            ]
            for (name, category) in catalog {
                context.insert(Exercise(name: name, category: category))
            }
            guard (try? context.save()) != nil else { return }
        }
        defaults.set(true, forKey: "barbellledger.catalog.seeded.v1")
    }

    static func createWorkout(from routine: Routine?, context: ModelContext) throws -> Workout {
        let workout = Workout(name: routine?.name ?? "", routine: routine)
        context.insert(workout)
        if let routine {
            for entry in routine.orderedEntries {
                guard let exercise = entry.exercise else { continue }
                let item = WorkoutExercise(exercise: exercise, order: entry.order)
                item.notes = entry.exercise?.notes ?? ""
                item.restSeconds = entry.restSeconds
                workout.exercises?.append(item)
                for setIndex in 0..<max(1, entry.targetSets) {
                    let set = WorkoutSet(order: setIndex, reps: entry.targetReps, rpe: entry.targetRPE)
                    item.sets?.append(set)
                }
            }
        }
        do {
            try context.save()
            return workout
        } catch {
            context.delete(workout)
            throw error
        }
    }

    static func reindex(_ exercises: [WorkoutExercise]) {
        for (index, exercise) in exercises.enumerated() { exercise.order = index }
    }

    static func reindex(_ entries: [RoutineExercise]) {
        for (index, entry) in entries.enumerated() { entry.order = index }
    }
}
