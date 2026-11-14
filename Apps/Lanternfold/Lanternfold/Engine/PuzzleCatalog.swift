import Foundation

/// A calendar day in the player's own time zone.
struct DayStamp: Codable, Sendable, Hashable, Comparable {
    let year: Int
    let month: Int
    let day: Int

    /// The first day of the daily archive.
    static let epoch = DayStamp(year: 2026, month: 10, day: 1)

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init(date: Date, timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 2026, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    static var today: DayStamp { DayStamp(date: .now) }

    static func < (lhs: DayStamp, rhs: DayStamp) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    var key: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Noon UTC on this calendar day; used only for day arithmetic and display.
    var anchorDate: Date {
        Self.utcCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .distantPast
    }

    func adding(days: Int) -> DayStamp {
        let moved = Self.utcCalendar.date(byAdding: .day, value: days, to: anchorDate) ?? anchorDate
        return DayStamp(date: moved, timeZone: Self.utcCalendar.timeZone)
    }

    func days(since other: DayStamp) -> Int {
        Self.utcCalendar.dateComponents([.day], from: other.anchorDate, to: anchorDate).day ?? 0
    }

    /// 1 for the first archive day.
    var number: Int { days(since: .epoch) + 1 }

    /// 1 = Sunday ... 7 = Saturday.
    var weekday: Int {
        Self.utcCalendar.component(.weekday, from: anchorDate)
    }

    var displayText: String {
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted)
        style.timeZone = Self.utcCalendar.timeZone
        return anchorDate.formatted(style.weekday(.abbreviated))
    }
}

struct JourneyPack: Sendable, Identifiable {
    let index: Int
    let name: String
    let blurb: String
    let size: Int
    let stones: StonePolicy
    let levelCount: Int
    let isFree: Bool

    var id: Int { index }

    func difficulty(level: Int) -> Difficulty {
        let progress = Double(level) / Double(levelCount)
        return progress < 0.35 ? .easy : (progress < 0.7 ? .medium : .hard)
    }

    static let all: [JourneyPack] = [
        JourneyPack(index: 0, name: "Seedlings", blurb: "Small gardens to learn the rules.", size: 5, stones: .none, levelCount: 20, isFree: true),
        JourneyPack(index: 1, name: "Courtyard", blurb: "Six plots, six lanterns.", size: 6, stones: .none, levelCount: 30, isFree: true),
        JourneyPack(index: 2, name: "Stepping Stones", blurb: "Numbered stones join the garden.", size: 6, stones: .required, levelCount: 20, isFree: true),
        JourneyPack(index: 3, name: "Terrace", blurb: "Wider gardens with the odd stone.", size: 7, stones: .allowed, levelCount: 40, isFree: false),
        JourneyPack(index: 4, name: "Orchard", blurb: "Eight rows of careful deduction.", size: 8, stones: .allowed, levelCount: 40, isFree: false),
        JourneyPack(index: 5, name: "Estate", blurb: "The largest gardens of all.", size: 9, stones: .allowed, levelCount: 40, isFree: false)
    ]

    static var totalLevels: Int { all.reduce(0) { $0 + $1.levelCount } }
}

enum PuzzleSource: Sendable, Hashable {
    case daily(DayStamp)
    case journey(pack: Int, level: Int)
    case endless(id: String, request: GeneratorRequest)

    /// Free players may open today's puzzle and the two days before it.
    static let freeArchiveDays = 2

    var key: String {
        switch self {
        case .daily(let day): "daily:\(day.key)"
        case .journey(let pack, let level): "journey:\(pack):\(level)"
        case .endless(let id, _): "endless:\(id)"
        }
    }

    var kind: String {
        switch self {
        case .daily: "daily"
        case .journey: "journey"
        case .endless: "endless"
        }
    }

    /// Changing this text changes every generated puzzle; keep it stable across releases.
    var seedText: String {
        switch self {
        case .daily(let day): "lanternfold-daily-1-\(day.key)"
        case .journey(let pack, let level): "lanternfold-journey-1-\(pack)-\(level)"
        case .endless(let id, _): "lanternfold-endless-1-\(id)"
        }
    }

    var request: GeneratorRequest {
        switch self {
        case .daily(let day):
            switch day.weekday {
            case 2: GeneratorRequest(size: 6, difficulty: .easy, stones: .none)
            case 3: GeneratorRequest(size: 7, difficulty: .easy, stones: .allowed)
            case 4: GeneratorRequest(size: 7, difficulty: .medium, stones: .allowed)
            case 5: GeneratorRequest(size: 8, difficulty: .medium, stones: .allowed)
            case 6: GeneratorRequest(size: 8, difficulty: .hard, stones: .allowed)
            case 7: GeneratorRequest(size: 9, difficulty: .medium, stones: .allowed)
            default: GeneratorRequest(size: 9, difficulty: .hard, stones: .allowed)
            }
        case .journey(let pack, let level):
            if let item = JourneyPack.all.first(where: { $0.index == pack }) {
                GeneratorRequest(size: item.size, difficulty: item.difficulty(level: level), stones: item.stones)
            } else {
                GeneratorRequest(size: 6, difficulty: .easy, stones: .none)
            }
        case .endless(_, let request):
            request
        }
    }

    var title: String {
        switch self {
        case .daily(let day):
            "Daily #\(day.number)"
        case .journey(let pack, let level):
            "\(JourneyPack.all.first(where: { $0.index == pack })?.name ?? "Journey") \(level + 1)"
        case .endless:
            "Endless"
        }
    }

    func isUnlocked(isPro: Bool, today: DayStamp = .today) -> Bool {
        if isPro { return true }
        switch self {
        case .daily(let day):
            return day <= today && today.days(since: day) <= Self.freeArchiveDays
        case .journey(let pack, _):
            return JourneyPack.all.first(where: { $0.index == pack })?.isFree ?? false
        case .endless:
            return false
        }
    }

    /// The puzzle that naturally follows this one, if any.
    var next: PuzzleSource? {
        guard case .journey(let pack, let level) = self,
              let item = JourneyPack.all.first(where: { $0.index == pack }),
              level + 1 < item.levelCount else { return nil }
        return .journey(pack: pack, level: level + 1)
    }
}

enum PuzzleFactory {
    /// Builds the puzzle for a source off the main actor. The same source always yields the same puzzle.
    static func make(_ source: PuzzleSource) async -> Puzzle {
        let seed = source.seedText
        let request = source.request
        return await Task.detached(priority: .userInitiated) {
            var random = SeededRandom(text: seed)
            return PuzzleGenerator.generate(request, random: &random)
        }.value
    }
}
