import Foundation

enum Difficulty: Int, Codable, Sendable, CaseIterable, Comparable {
    case easy = 1
    case medium = 2
    case hard = 3

    static func < (lhs: Difficulty, rhs: Difficulty) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var title: String {
        switch self {
        case .easy: "Gentle"
        case .medium: "Steady"
        case .hard: "Tricky"
        }
    }
}

/// A square garden. Every row, column and coloured plot holds exactly one lantern,
/// lanterns never touch (not even diagonally), and a stone states how many lanterns
/// stand in the cells around it. Each puzzle has exactly one solution.
struct Puzzle: Codable, Sendable, Equatable {
    let size: Int
    /// Plot index (0..<size) for every cell, row-major.
    let regions: [Int]
    /// Stone cells and the number of lanterns around each of them.
    let stones: [Int: Int]
    /// Lantern column for every row.
    let solution: [Int]
    let difficulty: Difficulty

    var cellCount: Int { size * size }

    func row(of cell: Int) -> Int { cell / size }
    func column(of cell: Int) -> Int { cell % size }

    var solutionCells: Set<Int> {
        Set(solution.enumerated().map { $0.offset * size + $0.element })
    }
}
