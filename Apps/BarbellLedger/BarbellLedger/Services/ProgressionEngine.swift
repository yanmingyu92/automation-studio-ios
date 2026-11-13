import Foundation

struct ProgressionSuggestion {
    let weightKilograms: Double
    let targetReps: Int
    let reason: String
    let isDeload: Bool
}

struct PersonalRecord: Hashable {
    let label: String
    let valueKilograms: Double
}

enum ProgressionEngine {
    static func previousExercise(before workout: Workout, matching item: WorkoutExercise, in workouts: [Workout]) -> WorkoutExercise? {
        workouts
            .filter { candidate in
                guard candidate.id != workout.id, let completedAt = candidate.completedAt else { return false }
                return completedAt < workout.startedAt
            }
            .sorted { ($0.completedAt ?? $0.startedAt) > ($1.completedAt ?? $1.startedAt) }
            .flatMap(\.orderedExercises)
            .first { previous in
                previous.matches(item) && previous.orderedSets.contains { $0.isCompleted && $0.kind != .warmup }
            }
    }

    static func suggestion(for item: WorkoutExercise, in workout: Workout, workouts: [Workout]) -> ProgressionSuggestion? {
        guard let exercise = item.exercise, let rule = exercise.progressionRule, rule.isEnabled,
              let previous = previousExercise(before: workout, matching: item, in: workouts) else { return nil }
        let sets = previous.orderedSets.filter { $0.isCompleted && $0.kind != .warmup && $0.weightKilograms > 0 && $0.reps > 0 }
        guard !sets.isEmpty else { return nil }
        guard let topSet = sets.max(by: { $0.estimatedOneRepMaxKilograms < $1.estimatedOneRepMaxKilograms }) else { return nil }

        let weeks = Set(workouts.filter { $0.completedAt != nil && $0.startedAt <= workout.startedAt }.map { $0.startedAt.trainingWeek })
        let currentWeek = workout.startedAt.trainingWeek
        let weekNumber = weeks.contains(currentWeek) ? weeks.count : weeks.count + 1
        let isSameTrainingWeek = previous.workout?.startedAt.trainingWeek == currentWeek
        let rounding = max(0.01, rule.roundingIncrementKilograms)
        let loggedRPE = sets.compactMap(\.rpe)
        let averageRPE = loggedRPE.isEmpty ? nil : loggedRPE.reduce(0, +) / Double(loggedRPE.count)
        let reachedTopReps = sets.allSatisfy { $0.reps >= rule.maximumReps }
        let rpeWasControlled = averageRPE.map { $0 <= rule.rpeCeiling } ?? true

        if rule.deloadEveryWeeks > 1, weekNumber % rule.deloadEveryWeeks == 0 {
            let weight = isSameTrainingWeek ? topSet.weightKilograms : rounded(topSet.weightKilograms * (1 - rule.deloadFraction), to: rounding)
            let reason = isSameTrainingWeek
                ? "Week \(weekNumber) is your scheduled deload. The last session was in the same training week, so its reduced weight is held instead of deloading twice. You can override it."
                : "Week \(weekNumber) starts a scheduled deload every \(rule.deloadEveryWeeks) training weeks: \(Int(rule.deloadFraction * 100))% below your last top set (\(topSet.weightKilograms.cleanString) kg). You can override it."
            return ProgressionSuggestion(weightKilograms: weight, targetReps: rule.minimumReps, reason: reason, isDeload: true)
        }

        if isSameTrainingWeek {
            return ProgressionSuggestion(
                weightKilograms: topSet.weightKilograms,
                targetReps: min(max(topSet.reps, rule.minimumReps), rule.maximumReps),
                reason: "The last session was in this training week. Weekly progression allows at most one increase per week, so the last top-set weight is held. You can override it.",
                isDeload: false
            )
        }

        if reachedTopReps && rpeWasControlled {
            let weight = rounded(topSet.weightKilograms + rule.weeklyIncrementKilograms, to: rounding)
            let rpeText = averageRPE.map { " Average logged RPE was \($0.cleanString), within your ≤\(rule.rpeCeiling.cleanString) ceiling." } ?? " No RPE was logged, so the RPE ceiling was not evaluated."
            return ProgressionSuggestion(
                weightKilograms: weight,
                targetReps: rule.minimumReps,
                reason: "All \(sets.count) previous working sets reached \(rule.maximumReps) reps.\(rpeText) Added \(rule.weeklyIncrementKilograms.cleanString) kg to the last top set. You can override it.",
                isDeload: false
            )
        }

        let explanation: String
        if !reachedTopReps {
            explanation = "Not every previous working set reached the \(rule.maximumReps)-rep target"
        } else {
            explanation = "Average RPE \(averageRPE?.cleanString ?? "—") exceeded your \(rule.rpeCeiling.cleanString) ceiling"
        }
        return ProgressionSuggestion(
            weightKilograms: rounded(topSet.weightKilograms, to: rounding),
            targetReps: min(max(topSet.reps, rule.minimumReps), rule.maximumReps),
            reason: "\(explanation), so the last top-set weight is held. Log the result and adjust any set manually.",
            isDeload: false
        )
    }

    static func rounded(_ weight: Double, to increment: Double) -> Double {
        max(0, (weight / increment).rounded() * increment)
    }
}

enum PersonalRecordDetector {
    static func detect(for set: WorkoutSet, item: WorkoutExercise, workout: Workout, workouts: [Workout]) -> [PersonalRecord] {
        guard set.isCompleted, set.kind != .warmup, set.weightKilograms > 0, set.reps > 0 else { return [] }
        let previousSessions = workouts
            .filter { candidate in
                guard candidate.id != workout.id, let completedAt = candidate.completedAt else { return false }
                return completedAt < workout.startedAt
            }
            .flatMap(\.orderedExercises)
            .filter { $0.matches(item) }
            .flatMap(\.orderedSets)
        let earlierCurrentSets = workout.orderedExercises
            .filter { $0.matches(item) }
            .flatMap(\.orderedSets)
            .filter { candidate in
                guard candidate.id != set.id, candidate.isCompleted, candidate.kind != .warmup else { return false }
                guard let candidateDate = candidate.completedAt, let setDate = set.completedAt else { return candidate.order < set.order }
                return candidateDate < setDate || (candidateDate == setDate && candidate.order < set.order)
            }
        let historical = (previousSessions + earlierCurrentSets)
            .filter { $0.id != set.id && $0.isCompleted && $0.kind != .warmup }
        let previousWeight = historical.map(\.weightKilograms).max() ?? 0
        let previousE1RM = historical.map(\.estimatedOneRepMaxKilograms).max() ?? 0
        let previousRepsAtWeight = historical.filter { abs($0.weightKilograms - set.weightKilograms) < 0.001 }.map(\.reps).max() ?? 0
        var records: [PersonalRecord] = []
        if set.weightKilograms > previousWeight {
            records.append(PersonalRecord(label: "Weight PR", valueKilograms: set.weightKilograms))
        }
        if set.estimatedOneRepMaxKilograms > previousE1RM {
            records.append(PersonalRecord(label: "Estimated 1RM PR", valueKilograms: set.estimatedOneRepMaxKilograms))
        }
        if set.reps > previousRepsAtWeight, previousRepsAtWeight > 0 {
            records.append(PersonalRecord(label: "Rep PR", valueKilograms: set.weightKilograms))
        }
        return records
    }
}
