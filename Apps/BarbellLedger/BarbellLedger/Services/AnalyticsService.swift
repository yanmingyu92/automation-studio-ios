import Foundation

struct VolumePoint: Identifiable {
    let date: Date
    let volumeKilograms: Double
    var id: Date { date }
}

struct OneRepMaxPoint: Identifiable {
    let date: Date
    let valueKilograms: Double
    var id: Date { date }
}

struct PRChartPoint: Identifiable {
    let date: Date
    let count: Int
    var id: Date { date }
}

struct PersonalRecordEvent: Identifiable {
    let id: UUID
    let date: Date
    let exerciseName: String
    let labels: [String]
    let weightKilograms: Double
    let reps: Int
}

enum AnalyticsService {
    static func volumeByWeek(workouts: [Workout], weeks: Int = 12, now: Date = .now) -> [VolumePoint] {
        let calendar = Calendar.current
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start,
              let firstWeek = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: thisWeek) else { return [] }
        var totals: [Date: Double] = [:]
        for workout in workouts where workout.completedAt != nil && workout.startedAt >= firstWeek {
            guard let week = calendar.dateInterval(of: .weekOfYear, for: workout.startedAt)?.start else { continue }
            totals[week, default: 0] += workout.completedSets.reduce(0) { $0 + $1.volumeKilograms }
        }
        return (0..<weeks).compactMap { offset in
            guard let week = calendar.date(byAdding: .weekOfYear, value: offset, to: firstWeek) else { return nil }
            return VolumePoint(date: week, volumeKilograms: totals[week, default: 0])
        }
    }

    static func oneRepMaxPoints(workouts: [Workout], exercise: Exercise?) -> [OneRepMaxPoint] {
        guard let exercise else { return [] }
        return workouts
            .filter { $0.completedAt != nil }
            .sorted { $0.startedAt < $1.startedAt }
            .compactMap { workout in
                let sets = workout.orderedExercises
                    .filter { $0.matches(exercise) }
                    .flatMap(\.orderedSets)
                    .filter { $0.isCompleted && $0.kind != .warmup && $0.estimatedOneRepMaxKilograms > 0 }
                guard let best = sets.map(\.estimatedOneRepMaxKilograms).max(), best > 0 else { return nil }
                return OneRepMaxPoint(date: workout.startedAt, valueKilograms: best)
            }
    }

    static func personalRecordEvents(workouts: [Workout]) -> [PersonalRecordEvent] {
        let orderedWorkouts = workouts.filter { $0.completedAt != nil }.sorted { $0.startedAt < $1.startedAt }
        var maxWeights: [String: Double] = [:]
        var maxE1RM: [String: Double] = [:]
        var maxReps: [String: [Int: Int]] = [:]
        var events: [PersonalRecordEvent] = []
        for workout in orderedWorkouts {
            for item in workout.orderedExercises {
                let key = item.exerciseName.foldingForAnalytics
                for set in item.orderedSets.filter({ $0.isCompleted && $0.kind != .warmup && $0.weightKilograms > 0 && $0.reps > 0 }) {
                    var labels: [String] = []
                    if set.weightKilograms > (maxWeights[key] ?? 0) {
                        labels.append("Weight PR")
                        maxWeights[key] = set.weightKilograms
                    }
                    if set.estimatedOneRepMaxKilograms > (maxE1RM[key] ?? 0) {
                        labels.append("Estimated 1RM PR")
                        maxE1RM[key] = set.estimatedOneRepMaxKilograms
                    }
                    let weightKey = Int((set.weightKilograms * 1000).rounded())
                    let previousReps = maxReps[key]?[weightKey] ?? 0
                    if set.reps > previousReps {
                        if previousReps > 0 { labels.append("Rep PR") }
                        maxReps[key, default: [:]][weightKey] = set.reps
                    }
                    if !labels.isEmpty {
                        events.append(PersonalRecordEvent(id: set.id, date: set.completedAt ?? workout.startedAt, exerciseName: item.exerciseName, labels: labels, weightKilograms: set.weightKilograms, reps: set.reps))
                    }
                }
            }
        }
        return events.sorted { $0.date > $1.date }
    }

    static func prCountsByMonth(events: [PersonalRecordEvent], months: Int = 6, now: Date = .now) -> [PRChartPoint] {
        let calendar = Calendar.current
        guard let thisMonth = calendar.dateInterval(of: .month, for: now)?.start,
              let first = calendar.date(byAdding: .month, value: -(months - 1), to: thisMonth) else { return [] }
        var counts: [Date: Int] = [:]
        for event in events where event.date >= first {
            guard let month = calendar.dateInterval(of: .month, for: event.date)?.start else { continue }
            counts[month, default: 0] += event.labels.count
        }
        return (0..<months).compactMap { offset in
            guard let month = calendar.date(byAdding: .month, value: offset, to: first) else { return nil }
            return PRChartPoint(date: month, count: counts[month, default: 0])
        }
    }
}

private extension String {
    var foldingForAnalytics: String {
        trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}
