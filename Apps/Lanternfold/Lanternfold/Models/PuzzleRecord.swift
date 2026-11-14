import Foundation
import SwiftData

/// Saved state of one puzzle: the generated garden, the player's marks and the result.
@Model
final class PuzzleRecord {
    @Attribute(.unique) var key: String
    var kind: String
    var title: String
    var size: Int
    var difficultyRaw: Int
    var puzzleData: Data
    var marksData: Data
    var elapsed: Double
    var hintsUsed: Int
    var startedAt: Date
    var updatedAt: Date
    var completedAt: Date?
    /// For daily puzzles: solved on the puzzle's own calendar day (counts toward the streak).
    var completedOnDay: Bool
    var dayKey: String?

    init(source: PuzzleSource, puzzle: Puzzle) throws {
        key = source.key
        kind = source.kind
        title = source.title
        size = puzzle.size
        difficultyRaw = puzzle.difficulty.rawValue
        puzzleData = try JSONEncoder().encode(puzzle)
        marksData = Data(repeating: 0, count: puzzle.cellCount)
        elapsed = 0
        hintsUsed = 0
        startedAt = .now
        updatedAt = .now
        completedAt = nil
        completedOnDay = false
        if case .daily(let day) = source {
            dayKey = day.key
        } else {
            dayKey = nil
        }
    }

    var puzzle: Puzzle? {
        try? JSONDecoder().decode(Puzzle.self, from: puzzleData)
    }

    var difficulty: Difficulty {
        Difficulty(rawValue: difficultyRaw) ?? .easy
    }

    var isComplete: Bool { completedAt != nil }

    var isStarted: Bool {
        elapsed > 0 || marksData.contains { $0 != 0 }
    }
}

struct ProgressSummary {
    struct SizeBest: Identifiable {
        let size: Int
        let solved: Int
        let best: Double
        let average: Double
        var id: Int { size }
    }

    let solvedTotal: Int
    let solvedDaily: Int
    let solvedJourney: Int
    let solvedEndless: Int
    let solvedWithoutHints: Int
    let totalTime: Double
    let currentStreak: Int
    let longestStreak: Int
    let bySize: [SizeBest]

    init(records: [PuzzleRecord], today: DayStamp = .today) {
        let solved = records.filter(\.isComplete)
        solvedTotal = solved.count
        solvedDaily = solved.filter { $0.kind == "daily" }.count
        solvedJourney = solved.filter { $0.kind == "journey" }.count
        solvedEndless = solved.filter { $0.kind == "endless" }.count
        solvedWithoutHints = solved.filter { $0.hintsUsed == 0 }.count
        totalTime = records.reduce(0) { $0 + $1.elapsed }

        let streakDays = Set(solved.filter { $0.kind == "daily" && $0.completedOnDay }.compactMap(\.dayKey))
        var current = 0
        var cursor = streakDays.contains(today.key) ? today : today.adding(days: -1)
        while streakDays.contains(cursor.key) {
            current += 1
            cursor = cursor.adding(days: -1)
        }
        currentStreak = current

        var longest = 0
        var run = 0
        var previous: String?
        for key in streakDays.sorted() {
            if let previous, Self.isNextDay(previous, key) {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
            previous = key
        }
        longestStreak = longest

        bySize = Dictionary(grouping: solved, by: \.size)
            .map { size, items in
                let times = items.map(\.elapsed)
                return SizeBest(size: size, solved: items.count, best: times.min() ?? 0, average: times.reduce(0, +) / Double(max(times.count, 1)))
            }
            .sorted { $0.size < $1.size }
    }

    private static func isNextDay(_ earlier: String, _ later: String) -> Bool {
        guard let day = stamp(from: earlier) else { return false }
        return day.adding(days: 1).key == later
    }

    private static func stamp(from key: String) -> DayStamp? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return DayStamp(year: parts[0], month: parts[1], day: parts[2])
    }
}

enum Clock {
    static func text(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Spoken form for VoiceOver.
    static func spoken(_ seconds: Double) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        return formatter.string(from: seconds.rounded(.down)) ?? text(seconds)
    }
}

extension PuzzleSource {
    /// Rebuilds the source of a saved puzzle from its key.
    init?(record: PuzzleRecord) {
        let parts = record.key.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        switch parts[0] {
        case "daily":
            let numbers = parts[1].split(separator: "-").compactMap { Int($0) }
            guard numbers.count == 3 else { return nil }
            self = .daily(DayStamp(year: numbers[0], month: numbers[1], day: numbers[2]))
        case "journey":
            let numbers = parts[1].split(separator: ":").compactMap { Int($0) }
            guard numbers.count == 2 else { return nil }
            self = .journey(pack: numbers[0], level: numbers[1])
        case "endless":
            self = .endless(id: parts[1], request: GeneratorRequest(size: record.size, difficulty: record.difficulty, stones: .allowed))
        default:
            return nil
        }
    }
}
