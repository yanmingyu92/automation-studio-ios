import Foundation
import Observation

enum Mark: UInt8, Sendable {
    case blank = 0
    case cross = 1
    case lantern = 2
}

struct ActiveHint: Equatable {
    let message: String
    /// Cells that explain the step (a row, a plot, a stone's surroundings).
    let context: Set<Int>
    /// Cells the step changes.
    let targets: Set<Int>
    let lanterns: [Int]
    let crosses: [Int]
    let clears: [Int]
}

@MainActor
@Observable
final class GameSession {
    private struct Change {
        let cell: Int
        let before: Mark
        let after: Mark
    }

    let source: PuzzleSource
    let puzzle: Puzzle
    let topology: Topology
    let record: PuzzleRecord
    private let solutionCells: Set<Int>

    private(set) var marks: [Mark]
    private(set) var isComplete: Bool
    private(set) var hintsUsed: Int
    private(set) var conflicts: Set<Int> = []
    private(set) var blocked: Set<Int> = []
    var hint: ActiveHint?
    /// Called after every saved change so the owner can write the store to disk.
    @ObservationIgnored var onPersist: (() -> Void)?

    private var undoStack: [[Change]] = []
    private var openGroup: [Change]?
    private var banked: Double
    private var runningSince: Date?

    init?(source: PuzzleSource, record: PuzzleRecord) {
        guard let puzzle = record.puzzle, record.marksData.count == puzzle.cellCount else { return nil }
        self.source = source
        self.puzzle = puzzle
        self.record = record
        topology = Topology(puzzle)
        solutionCells = puzzle.solutionCells
        marks = record.marksData.map { Mark(rawValue: $0) ?? .blank }
        isComplete = record.isComplete
        hintsUsed = record.hintsUsed
        banked = record.elapsed
        refreshDerived()
    }

    var canUndo: Bool { !undoStack.isEmpty && !isComplete }
    var hasMarks: Bool { marks.contains { $0 != .blank } }
    var lanternsPlaced: Int { marks.reduce(0) { $0 + ($1 == .lantern ? 1 : 0) } }

    // MARK: Clock

    func elapsed(at date: Date = .now) -> Double {
        banked + (runningSince.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }

    func resume() {
        guard !isComplete, runningSince == nil else { return }
        runningSince = .now
    }

    func pause() {
        if let runningSince {
            banked += max(0, Date.now.timeIntervalSince(runningSince))
            self.runningSince = nil
        }
        persist()
    }

    // MARK: Moves

    func isStone(_ cell: Int) -> Bool {
        topology.isStone[cell]
    }

    /// A tap cycles blank, cross, lantern (or lantern first, by preference).
    func tap(_ cell: Int, lanternFirst: Bool) {
        guard !isComplete, !isStone(cell) else { return }
        let next: Mark
        switch (marks[cell], lanternFirst) {
        case (.blank, false): next = .cross
        case (.cross, false): next = .lantern
        case (.lantern, false): next = .blank
        case (.blank, true): next = .lantern
        case (.lantern, true): next = .cross
        case (.cross, true): next = .blank
        }
        set(cell, to: next)
    }

    func set(_ cell: Int, to mark: Mark) {
        guard !isComplete, !isStone(cell), marks[cell] != mark else { return }
        let change = Change(cell: cell, before: marks[cell], after: mark)
        marks[cell] = mark
        if openGroup != nil {
            openGroup?.append(change)
        } else {
            undoStack.append([change])
        }
        hint = nil
        afterChange()
    }

    /// Groups the moves of one drag so a single undo reverts them.
    func beginGroup() {
        if openGroup == nil { openGroup = [] }
    }

    func endGroup() {
        if let group = openGroup, !group.isEmpty {
            undoStack.append(group)
        }
        openGroup = nil
    }

    func undo() {
        guard !isComplete, let group = undoStack.popLast() else { return }
        for change in group.reversed() {
            marks[change.cell] = change.before
        }
        hint = nil
        afterChange()
    }

    func clearBoard() {
        guard !isComplete, hasMarks else { return }
        // One mutation: clearing cell by cell could pass through the solved position.
        endGroup()
        let group = marks.indices.filter { marks[$0] != .blank }.map { Change(cell: $0, before: marks[$0], after: .blank) }
        for change in group {
            marks[change.cell] = .blank
        }
        undoStack.append(group)
        hint = nil
        afterChange()
    }

    private func afterChange() {
        refreshDerived()
        if Set(marks.indices.filter { marks[$0] == .lantern }) == solutionCells {
            complete()
        }
        persist()
    }

    private func refreshDerived() {
        var conflicts = Set<Int>()
        var blocked = Set<Int>()
        for cell in marks.indices where marks[cell] == .lantern {
            for peer in topology.peers[cell] {
                if marks[peer] == .lantern {
                    conflicts.insert(cell)
                } else if !topology.isStone[peer] {
                    blocked.insert(peer)
                }
            }
        }
        for stone in topology.stones {
            let around = topology.neighbors[stone.cell].reduce(0) { $0 + (marks[$1] == .lantern ? 1 : 0) }
            if around > stone.clue {
                conflicts.insert(stone.cell)
            }
        }
        self.conflicts = conflicts
        self.blocked = blocked
    }

    /// Lanterns currently standing around a stone.
    func lanternsAround(stoneAt cell: Int) -> Int {
        topology.neighbors[cell].reduce(0) { $0 + (marks[$1] == .lantern ? 1 : 0) }
    }

    private func complete() {
        if let runningSince {
            banked += max(0, Date.now.timeIntervalSince(runningSince))
            self.runningSince = nil
        }
        isComplete = true
        hint = nil
        undoStack.removeAll()
        record.completedAt = .now
        if case .daily(let day) = source {
            record.completedOnDay = day == DayStamp.today
        }
    }

    private func persist() {
        record.marksData = Data(marks.map(\.rawValue))
        record.elapsed = elapsed()
        record.hintsUsed = hintsUsed
        record.updatedAt = .now
        onPersist?()
    }

    // MARK: Hints

    func requestHint() {
        guard !isComplete, hint == nil else { return }
        hintsUsed += 1
        hint = makeHint()
        persist()
    }

    func applyHint() {
        guard let hint, !isComplete else { return }
        beginGroup()
        for cell in hint.clears { set(cell, to: .blank) }
        for cell in hint.crosses { set(cell, to: .cross) }
        for cell in hint.lanterns { set(cell, to: .lantern) }
        endGroup()
        self.hint = nil
    }

    private func makeHint() -> ActiveHint {
        let wrongLanterns = marks.indices.filter { marks[$0] == .lantern && !solutionCells.contains($0) }
        if let cell = wrongLanterns.first {
            return ActiveHint(
                message: "This lantern cannot stay here. Take it away and look again.",
                context: [], targets: [cell], lanterns: [], crosses: [], clears: [cell]
            )
        }
        let wrongCrosses = marks.indices.filter { marks[$0] == .cross && solutionCells.contains($0) }
        if let cell = wrongCrosses.first {
            return ActiveHint(
                message: "This cell was ruled out too early. Clear the mark.",
                context: [], targets: [cell], lanterns: [], crosses: [], clears: [cell]
            )
        }

        var grid = SolverGrid(topology: topology)
        for cell in marks.indices where marks[cell] == .lantern {
            grid.place(cell)
        }
        for cell in marks.indices where marks[cell] == .cross {
            grid.eliminate(cell)
        }
        guard let step = grid.nextDeduction(maxLevel: 3) else {
            let cell = solutionCells.sorted().first { marks[$0] != .lantern } ?? 0
            return ActiveHint(
                message: "A lantern belongs here.",
                context: [], targets: [cell], lanterns: [cell], crosses: [], clears: []
            )
        }

        let message: String
        var context = Set<Int>()
        switch step.reason {
        case .single(let unit):
            context = Set(topology.units[unit])
            message = "Only one cell is left for a lantern in \(name(ofUnit: unit))."
        case .stoneNeedsAll(let index):
            let stone = topology.stones[index]
            context = Set(topology.neighbors[stone.cell]).union([stone.cell])
            let missing = step.lanterns.count
            message = "This stone still needs \(missing) \(missing == 1 ? "lantern" : "lanterns"), and exactly that many open cells touch it."
        case .stoneFull(let index):
            let stone = topology.stones[index]
            context = Set(topology.neighbors[stone.cell]).union([stone.cell])
            message = stone.clue == 0
                ? "This stone shows 0, so no lantern may touch it."
                : "This stone already has all its lanterns, so the other cells around it stay empty."
        case .confined(let unit, let into):
            context = Set(topology.units[into])
            message = "Every open cell of \(name(ofUnit: unit)) lies in \(name(ofUnit: into)), so the rest of \(name(ofUnit: into)) stays empty."
        case .probe(_, let failure):
            switch failure {
            case .unit(let unit):
                context = Set(topology.units[unit])
                message = "A lantern here would leave \(name(ofUnit: unit)) with no room for its own lantern."
            case .stone(let index):
                let stone = topology.stones[index]
                context = Set(topology.neighbors[stone.cell]).union([stone.cell])
                message = "A lantern here would make this stone's number impossible."
            case .clash:
                message = "A lantern here would force two lanterns to see or touch each other."
            }
        }
        return ActiveHint(
            message: message,
            context: context,
            targets: Set(step.lanterns + step.eliminated),
            lanterns: step.lanterns,
            crosses: step.eliminated,
            clears: []
        )
    }

    private func name(ofUnit unit: Int) -> String {
        let index = topology.index(ofUnit: unit)
        switch topology.kind(ofUnit: unit) {
        case .row: return "row \(index + 1)"
        case .column: return "column \(index + 1)"
        case .plot: return "the \(Palette.plotName(index)) plot"
        }
    }

    // MARK: Sharing

    /// A spoiler-free result: the plot map of the garden, never the lantern positions.
    func shareText(streak: Int) -> String {
        let squares = ["🟨", "🟥", "🟦", "🟩", "🟪", "🟧", "🟫", "⬜", "⬛"]
        var lines = ["Lanternfold \(source.title) · \(puzzle.size)×\(puzzle.size) \(puzzle.difficulty.title)"]
        var result = "🏮 \(Clock.text(elapsed())) · " + (hintsUsed == 0 ? "no hints" : "💡×\(hintsUsed)")
        if streak > 1 { result += " · 🔥\(streak)" }
        lines.append(result)
        for row in 0..<puzzle.size {
            lines.append((0..<puzzle.size).map { squares[puzzle.regions[row * puzzle.size + $0] % squares.count] }.joined())
        }
        return lines.joined(separator: "\n")
    }
}
