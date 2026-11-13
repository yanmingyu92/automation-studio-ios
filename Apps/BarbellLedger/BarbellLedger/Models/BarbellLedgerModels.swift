import Foundation
import SwiftData

enum WeightUnit: String, CaseIterable, Identifiable, Codable {
    case kilograms = "kg"
    case pounds = "lb"

    var id: String { rawValue }
    var label: String { rawValue }
    var kilogramsPerUnit: Double { self == .kilograms ? 1 : 0.45359237 }

    func fromKilograms(_ value: Double) -> Double {
        value / kilogramsPerUnit
    }

    func toKilograms(_ value: Double) -> Double {
        value * kilogramsPerUnit
    }
}

enum SetKind: String, CaseIterable, Identifiable, Codable {
    case working
    case warmup
    case drop
    case failure

    var id: String { rawValue }
    var label: String {
        switch self {
        case .working: "Working"
        case .warmup: "Warm-up"
        case .drop: "Drop"
        case .failure: "Failure"
        }
    }

    var shortLabel: String {
        switch self {
        case .working: "W"
        case .warmup: "WU"
        case .drop: "D"
        case .failure: "F"
        }
    }
}

enum ExerciseCategory: String, CaseIterable, Identifiable, Codable {
    case chest = "Chest"
    case back = "Back"
    case shoulders = "Shoulders"
    case arms = "Arms"
    case legs = "Legs"
    case core = "Core"
    case olympic = "Olympic"
    case cardio = "Cardio"
    case other = "Other"

    var id: String { rawValue }
}

@Model
final class Exercise {
    @Attribute(.unique) var id: UUID
    var name: String
    var categoryRaw: String
    var notes: String
    var isArchived: Bool
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \RoutineExercise.exercise)
    var routineEntries: [RoutineExercise]? = []

    @Relationship(deleteRule: .nullify, inverse: \WorkoutExercise.exercise)
    var workoutExercises: [WorkoutExercise]? = []

    @Relationship(deleteRule: .cascade, inverse: \ProgressionRule.exercise)
    var progressionRules: [ProgressionRule]? = []

    init(name: String, category: ExerciseCategory = .other, notes: String = "") {
        self.id = UUID()
        self.name = name
        self.categoryRaw = category.rawValue
        self.notes = notes
        self.isArchived = false
        self.createdAt = .now
    }

    var category: ExerciseCategory {
        get { ExerciseCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var progressionRule: ProgressionRule? { progressionRules?.first }
}

@Model
final class Routine {
    @Attribute(.unique) var id: UUID
    var name: String
    var notes: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \RoutineExercise.routine)
    var entries: [RoutineExercise]? = []

    @Relationship(deleteRule: .nullify, inverse: \Workout.routine)
    var workouts: [Workout]? = []

    init(name: String, notes: String = "") {
        self.id = UUID()
        self.name = name
        self.notes = notes
        self.createdAt = .now
        self.updatedAt = .now
    }

    var orderedEntries: [RoutineExercise] {
        (entries ?? []).sorted { $0.order < $1.order }
    }
}

@Model
final class RoutineExercise {
    @Attribute(.unique) var id: UUID
    var exerciseName: String
    var order: Int
    var targetSets: Int
    var targetReps: Int
    var targetRPE: Double?
    var restSeconds: Int
    var routine: Routine?
    var exercise: Exercise?

    init(exercise: Exercise, order: Int, targetSets: Int = 3, targetReps: Int = 8, targetRPE: Double? = 8, restSeconds: Int = 120) {
        self.id = UUID()
        self.exercise = exercise
        self.exerciseName = exercise.name
        self.order = order
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.targetRPE = targetRPE
        self.restSeconds = restSeconds
    }
}

@Model
final class Workout {
    @Attribute(.unique) var id: UUID
    var name: String
    var startedAt: Date
    var completedAt: Date?
    var notes: String
    var importFileHashes: [String] = []
    var routine: Routine?

    @Relationship(deleteRule: .cascade, inverse: \WorkoutExercise.workout)
    var exercises: [WorkoutExercise]? = []

    init(name: String = "Workout", startedAt: Date = .now, routine: Routine? = nil) {
        self.id = UUID()
        self.name = name
        self.startedAt = startedAt
        self.routine = routine
        self.completedAt = nil
        self.notes = ""
        self.importFileHashes = []
    }

    var orderedExercises: [WorkoutExercise] {
        (exercises ?? []).sorted { $0.order < $1.order }
    }

    var isActive: Bool { completedAt == nil }

    var allSets: [WorkoutSet] {
        orderedExercises.flatMap(\.orderedSets)
    }

    var completedSets: [WorkoutSet] {
        allSets.filter(\.isCompleted)
    }

    var duration: TimeInterval {
        max(0, (completedAt ?? .now).timeIntervalSince(startedAt))
    }
}

@Model
final class WorkoutExercise {
    @Attribute(.unique) var id: UUID
    var exerciseName: String
    var order: Int
    var notes: String
    var restSeconds: Int
    var workout: Workout?
    var exercise: Exercise?

    @Relationship(deleteRule: .cascade, inverse: \WorkoutSet.workoutExercise)
    var sets: [WorkoutSet]? = []

    init(exercise: Exercise, order: Int) {
        self.id = UUID()
        self.exercise = exercise
        self.exerciseName = exercise.name
        self.order = order
        self.notes = ""
        self.restSeconds = 90
    }

    var orderedSets: [WorkoutSet] {
        (sets ?? []).sorted { $0.order < $1.order }
    }

    func matches(_ other: WorkoutExercise) -> Bool {
        if let exerciseID = exercise?.id, let otherID = other.exercise?.id { return exerciseID == otherID }
        return exerciseName.caseInsensitiveCompare(other.exerciseName) == .orderedSame
    }

    func matches(_ exercise: Exercise) -> Bool {
        if let exerciseID = self.exercise?.id { return exerciseID == exercise.id }
        return exerciseName.caseInsensitiveCompare(exercise.name) == .orderedSame
    }
}

@Model
final class WorkoutSet {
    @Attribute(.unique) var id: UUID
    var order: Int
    var weightKilograms: Double
    var reps: Int
    var rpe: Double?
    var kindRaw: String
    var note: String
    var distanceMeters: Double
    var durationSeconds: TimeInterval
    var isCompleted: Bool
    var completedAt: Date?
    var personalRecordLabels: [String]
    var importFingerprint: String
    var importTimestamp: Date?
    var workoutExercise: WorkoutExercise?

    init(order: Int, weightKilograms: Double = 0, reps: Int = 0, rpe: Double? = nil, kind: SetKind = .working) {
        self.id = UUID()
        self.order = order
        self.weightKilograms = weightKilograms
        self.reps = reps
        self.rpe = rpe
        self.kindRaw = kind.rawValue
        self.note = ""
        self.distanceMeters = 0
        self.durationSeconds = 0
        self.isCompleted = false
        self.completedAt = nil
        self.personalRecordLabels = []
        self.importFingerprint = ""
        self.importTimestamp = nil
    }

    var kind: SetKind {
        get { SetKind(rawValue: kindRaw) ?? .working }
        set { kindRaw = newValue.rawValue }
    }

    var volumeKilograms: Double {
        isCompleted && kind != .warmup ? weightKilograms * Double(reps) : 0
    }

    var estimatedOneRepMaxKilograms: Double {
        guard isCompleted, kind != .warmup, weightKilograms > 0, reps > 0 else { return 0 }
        return weightKilograms * (1 + Double(reps) / 30)
    }
}

@Model
final class ProgressionRule {
    @Attribute(.unique) var id: UUID
    var isEnabled: Bool
    var weeklyIncrementKilograms: Double
    var roundingIncrementKilograms: Double
    var minimumReps: Int
    var maximumReps: Int
    var rpeCeiling: Double
    var deloadEveryWeeks: Int
    var deloadFraction: Double
    var exercise: Exercise?

    init(exercise: Exercise) {
        self.id = UUID()
        self.exercise = exercise
        self.isEnabled = false
        self.weeklyIncrementKilograms = 2.5
        self.roundingIncrementKilograms = 1.25
        self.minimumReps = 6
        self.maximumReps = 10
        self.rpeCeiling = 9
        self.deloadEveryWeeks = 4
        self.deloadFraction = 0.1
    }
}
