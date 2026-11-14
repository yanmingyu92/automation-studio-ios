import Foundation

struct Stone: Sendable, Equatable {
    let cell: Int
    let clue: Int
}

/// Precomputed structure of a puzzle. Units are indexed rows first, then columns, then plots.
struct Topology: Sendable {
    let size: Int
    let regions: [Int]
    let units: [[Int]]
    let cellUnits: [[Int]]
    let neighbors: [[Int]]
    let peers: [[Int]]
    let stones: [Stone]
    let isStone: [Bool]

    init(size: Int, regions: [Int], stones: [Int: Int]) {
        self.size = size
        self.regions = regions
        let count = size * size
        var units = Array(repeating: [Int](), count: size * 3)
        var cellUnits = Array(repeating: [Int](), count: count)
        for cell in 0..<count {
            let memberships = [cell / size, size + cell % size, size * 2 + regions[cell]]
            cellUnits[cell] = memberships
            for unit in memberships {
                units[unit].append(cell)
            }
        }
        var neighbors = Array(repeating: [Int](), count: count)
        for cell in 0..<count {
            let row = cell / size
            let column = cell % size
            for dr in -1...1 {
                for dc in -1...1 where dr != 0 || dc != 0 {
                    let r = row + dr
                    let c = column + dc
                    if r >= 0, r < size, c >= 0, c < size {
                        neighbors[cell].append(r * size + c)
                    }
                }
            }
        }
        var peers = Array(repeating: [Int](), count: count)
        for cell in 0..<count {
            var seen = Set<Int>()
            for unit in cellUnits[cell] {
                seen.formUnion(units[unit])
            }
            seen.formUnion(neighbors[cell])
            seen.remove(cell)
            peers[cell] = seen.sorted()
        }
        self.units = units
        self.cellUnits = cellUnits
        self.neighbors = neighbors
        self.peers = peers
        self.stones = stones.keys.sorted().map { Stone(cell: $0, clue: stones[$0] ?? 0) }
        var isStone = Array(repeating: false, count: count)
        for cell in stones.keys {
            isStone[cell] = true
        }
        self.isStone = isStone
    }

    init(_ puzzle: Puzzle) {
        self.init(size: puzzle.size, regions: puzzle.regions, stones: puzzle.stones)
    }

    enum UnitKind: Sendable {
        case row, column, plot
    }

    func kind(ofUnit unit: Int) -> UnitKind {
        unit < size ? .row : (unit < size * 2 ? .column : .plot)
    }

    func index(ofUnit unit: Int) -> Int {
        unit % size
    }
}

enum Contradiction: Sendable, Equatable {
    /// A row, column or plot has no cell left for its lantern.
    case unit(Int)
    /// A stone can no longer reach, or already exceeds, its number.
    case stone(Int)
    /// Two lanterns would see or touch each other at this cell.
    case clash(Int)
}

struct Deduction: Sendable, Equatable {
    enum Reason: Sendable, Equatable {
        case single(unit: Int)
        case stoneNeedsAll(stone: Int)
        case stoneFull(stone: Int)
        case confined(unit: Int, into: Int)
        case probe(cell: Int, breaks: Contradiction)
    }

    let reason: Reason
    let lanterns: [Int]
    let eliminated: [Int]

    var level: Int {
        switch reason {
        case .single, .stoneNeedsAll, .stoneFull: 1
        case .confined: 2
        case .probe: 3
        }
    }
}

struct SolverGrid: Sendable {
    static let unknown: UInt8 = 0
    static let lantern: UInt8 = 1
    static let empty: UInt8 = 2

    let topology: Topology
    private(set) var cells: [UInt8]

    init(topology: Topology) {
        self.topology = topology
        cells = Array(repeating: Self.unknown, count: topology.size * topology.size)
        for stone in topology.stones {
            cells[stone.cell] = Self.empty
        }
    }

    var lanternCount: Int {
        cells.reduce(0) { $0 + ($1 == Self.lantern ? 1 : 0) }
    }

    var isSolved: Bool {
        lanternCount == topology.size && !cells.contains(Self.unknown)
    }

    var lanternCells: [Int] {
        cells.indices.filter { cells[$0] == Self.lantern }
    }

    /// Places a lantern and rules out every cell it sees or touches.
    @discardableResult
    mutating func place(_ cell: Int) -> Bool {
        if cells[cell] == Self.empty { return false }
        cells[cell] = Self.lantern
        for peer in topology.peers[cell] {
            if cells[peer] == Self.lantern { return false }
            cells[peer] = Self.empty
        }
        return true
    }

    mutating func eliminate(_ cell: Int) {
        if cells[cell] == Self.unknown {
            cells[cell] = Self.empty
        }
    }

    func candidates(inUnit unit: Int) -> [Int] {
        topology.units[unit].filter { cells[$0] == Self.unknown }
    }

    func hasLantern(inUnit unit: Int) -> Bool {
        topology.units[unit].contains { cells[$0] == Self.lantern }
    }

    private func stoneStatus(_ stone: Stone) -> (lanterns: Int, open: [Int]) {
        var lanterns = 0
        var open = [Int]()
        for cell in topology.neighbors[stone.cell] {
            if cells[cell] == Self.lantern {
                lanterns += 1
            } else if cells[cell] == Self.unknown {
                open.append(cell)
            }
        }
        return (lanterns, open)
    }

    /// Other units that contain every remaining candidate of `unit`, with the cells this rules out.
    private func confinements(ofUnit unit: Int) -> [(into: Int, eliminated: [Int])] {
        guard !hasLantern(inUnit: unit) else { return [] }
        let open = candidates(inUnit: unit)
        guard open.count > 1 else { return [] }
        var shared = Set(topology.cellUnits[open[0]])
        for cell in open.dropFirst() {
            shared.formIntersection(topology.cellUnits[cell])
        }
        shared.remove(unit)
        var result = [(into: Int, eliminated: [Int])]()
        for other in shared.sorted() {
            let eliminated = candidates(inUnit: other).filter { !open.contains($0) }
            if !eliminated.isEmpty {
                result.append((other, eliminated))
            }
        }
        return result
    }

    /// Runs forced moves to a fixed point. Returns the contradiction if the position is impossible.
    mutating func propagate(confinement: Bool) -> Contradiction? {
        var changed = true
        while changed {
            changed = false
            for unit in topology.units.indices {
                var lanterns = 0
                var open = 0
                var last = -1
                for cell in topology.units[unit] {
                    if cells[cell] == Self.lantern {
                        lanterns += 1
                    } else if cells[cell] == Self.unknown {
                        open += 1
                        last = cell
                    }
                }
                guard lanterns == 0 else { continue }
                if open == 0 { return .unit(unit) }
                if open == 1 {
                    if !place(last) { return .clash(last) }
                    changed = true
                }
            }
            for (index, stone) in topology.stones.enumerated() {
                let status = stoneStatus(stone)
                if status.lanterns > stone.clue || status.lanterns + status.open.count < stone.clue {
                    return .stone(index)
                }
                guard !status.open.isEmpty else { continue }
                if status.lanterns == stone.clue {
                    for cell in status.open {
                        cells[cell] = Self.empty
                    }
                    changed = true
                } else if status.lanterns + status.open.count == stone.clue {
                    for cell in status.open where !place(cell) {
                        return .stone(index)
                    }
                    changed = true
                }
            }
            if confinement && !changed {
                for unit in topology.units.indices {
                    for item in confinements(ofUnit: unit) {
                        for cell in item.eliminated {
                            cells[cell] = Self.empty
                        }
                        changed = true
                    }
                }
            }
        }
        return nil
    }

    /// The simplest next logical step from this position, as a person would find it.
    func nextDeduction(maxLevel: Int = 3) -> Deduction? {
        for unit in topology.units.indices where !hasLantern(inUnit: unit) {
            let open = candidates(inUnit: unit)
            if open.count == 1 {
                return Deduction(reason: .single(unit: unit), lanterns: open, eliminated: [])
            }
        }
        for (index, stone) in topology.stones.enumerated() {
            let status = stoneStatus(stone)
            guard !status.open.isEmpty else { continue }
            if status.lanterns == stone.clue {
                return Deduction(reason: .stoneFull(stone: index), lanterns: [], eliminated: status.open)
            }
            if status.lanterns + status.open.count == stone.clue {
                return Deduction(reason: .stoneNeedsAll(stone: index), lanterns: status.open, eliminated: [])
            }
        }
        guard maxLevel >= 2 else { return nil }
        for unit in topology.units.indices {
            if let item = confinements(ofUnit: unit).first {
                return Deduction(reason: .confined(unit: unit, into: item.into), lanterns: [], eliminated: item.eliminated)
            }
        }
        guard maxLevel >= 3 else { return nil }
        for cell in cells.indices where cells[cell] == Self.unknown {
            var trial = self
            var failure: Contradiction?
            if trial.place(cell) {
                failure = trial.propagate(confinement: true)
            } else {
                failure = .clash(cell)
            }
            if let failure {
                return Deduction(reason: .probe(cell: cell, breaks: failure), lanterns: [], eliminated: [cell])
            }
        }
        return nil
    }

    mutating func apply(_ deduction: Deduction) {
        for cell in deduction.lanterns {
            place(cell)
        }
        for cell in deduction.eliminated {
            eliminate(cell)
        }
    }
}

enum PuzzleSolver {
    /// All solutions up to `limit`, each as the sorted list of lantern cells.
    static func solutions(topology: Topology, limit: Int) -> [[Int]] {
        var found = [[Int]]()
        search(SolverGrid(topology: topology), limit: limit, found: &found)
        return found
    }

    private static func search(_ start: SolverGrid, limit: Int, found: inout [[Int]]) {
        var grid = start
        if grid.propagate(confinement: false) != nil { return }
        if grid.isSolved {
            found.append(grid.lanternCells)
            return
        }
        var bestUnit = -1
        var bestCount = Int.max
        for unit in grid.topology.units.indices where !grid.hasLantern(inUnit: unit) {
            let count = grid.candidates(inUnit: unit).count
            if count < bestCount {
                bestCount = count
                bestUnit = unit
            }
        }
        guard bestUnit >= 0 else { return }
        for cell in grid.candidates(inUnit: bestUnit) {
            var branch = grid
            if branch.place(cell) {
                search(branch, limit: limit, found: &found)
                if found.count >= limit { return }
            }
        }
    }

    struct Rating: Sendable {
        let solved: Bool
        let level: Int
        let steps: Int
        let probes: Int
    }

    /// Solves with human techniques only and reports the hardest one needed.
    static func rate(topology: Topology) -> Rating {
        var grid = SolverGrid(topology: topology)
        var level = 1
        var steps = 0
        var probes = 0
        while !grid.isSolved {
            guard let deduction = grid.nextDeduction(maxLevel: 3) else {
                return Rating(solved: false, level: level, steps: steps, probes: probes)
            }
            level = max(level, deduction.level)
            steps += 1
            if deduction.level == 3 { probes += 1 }
            grid.apply(deduction)
        }
        return Rating(solved: true, level: level, steps: steps, probes: probes)
    }
}
