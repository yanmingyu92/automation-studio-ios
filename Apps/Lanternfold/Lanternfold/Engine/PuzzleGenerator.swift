import Foundation

enum StonePolicy: Int, Codable, Sendable, Hashable {
    case none
    case allowed
    case required
}

struct GeneratorRequest: Codable, Sendable, Hashable {
    var size: Int
    var difficulty: Difficulty?
    var stones: StonePolicy
}

enum PuzzleGenerator {
    static let supportedSizes = 5...9

    static func generate(_ request: GeneratorRequest, random: inout SeededRandom) -> Puzzle {
        let size = min(max(request.size, supportedSizes.lowerBound), supportedSizes.upperBound)
        var fallback: Puzzle?
        var fallbackDistance = Int.max
        var attempt = 0
        while true {
            attempt += 1
            // After many misses, relax the stone rule so generation always terminates quickly.
            let policy: StonePolicy = (request.stones == .none && attempt > 600) ? .allowed : request.stones
            guard let candidate = attemptPuzzle(size: size, policy: policy, random: &random) else { continue }
            guard let wanted = request.difficulty else { return candidate }
            if candidate.difficulty == wanted { return candidate }
            let distance = abs(candidate.difficulty.rawValue - wanted.rawValue)
            if distance < fallbackDistance {
                fallbackDistance = distance
                fallback = candidate
            }
            if attempt >= 240, let fallback { return fallback }
        }
    }

    private static func attemptPuzzle(size: Int, policy: StonePolicy, random: inout SeededRandom) -> Puzzle? {
        guard let solution = randomSolution(size: size, random: &random) else { return nil }
        let solutionCells = solution.enumerated().map { $0.offset * size + $0.element }
        let regions = growRegions(size: size, seeds: solutionCells, random: &random)
        var stones = [Int: Int]()
        let lanternSet = Set(solutionCells)
        let base = Topology(size: size, regions: regions, stones: [:])

        func clue(for cell: Int) -> Int {
            base.neighbors[cell].reduce(0) { $0 + (lanternSet.contains($1) ? 1 : 0) }
        }

        let stoneLimit = max(2, size / 2)
        while true {
            let topology = Topology(size: size, regions: regions, stones: stones)
            let found = PuzzleSolver.solutions(topology: topology, limit: 2)
            if found.count == 1 { break }
            guard policy != .none, stones.count < stoneLimit,
                  let other = found.first(where: { Set($0) != lanternSet }) else { return nil }
            var wrong = other.filter { !lanternSet.contains($0) }
            guard !wrong.isEmpty else { return nil }
            random.shuffle(&wrong)
            stones[wrong[0]] = clue(for: wrong[0])
        }

        // Drop stones that turned out not to be needed.
        var order = stones.keys.sorted()
        random.shuffle(&order)
        for cell in order {
            var trial = stones
            trial.removeValue(forKey: cell)
            let topology = Topology(size: size, regions: regions, stones: trial)
            if PuzzleSolver.solutions(topology: topology, limit: 2).count == 1 {
                stones = trial
            }
        }
        if policy == .required && stones.isEmpty { return nil }

        let rating = PuzzleSolver.rate(topology: Topology(size: size, regions: regions, stones: stones))
        guard rating.solved else { return nil }
        let difficulty: Difficulty = rating.level >= 3 ? .hard : (rating.level == 2 ? .medium : .easy)
        return Puzzle(size: size, regions: regions, stones: stones, solution: solution, difficulty: difficulty)
    }

    /// One lantern per row and column with no two touching.
    private static func randomSolution(size: Int, random: inout SeededRandom) -> [Int]? {
        var columns = [Int]()
        var used = Array(repeating: false, count: size)

        func extend(_ random: inout SeededRandom) -> Bool {
            if columns.count == size { return true }
            var options = Array(0..<size)
            random.shuffle(&options)
            for column in options where !used[column] {
                if let previous = columns.last, abs(previous - column) < 2 { continue }
                used[column] = true
                columns.append(column)
                if extend(&random) { return true }
                columns.removeLast()
                used[column] = false
            }
            return false
        }

        return extend(&random) ? columns : nil
    }

    /// Grows one connected plot outward from each lantern until the garden is covered.
    private static func growRegions(size: Int, seeds: [Int], random: inout SeededRandom) -> [Int] {
        let count = size * size
        var regions = Array(repeating: -1, count: count)
        var weights = [Double]()
        for (index, cell) in seeds.enumerated() {
            regions[cell] = index
            let roll = random.unit()
            weights.append(0.25 + roll * roll * 3.0)
        }
        var remaining = count - seeds.count
        while remaining > 0 {
            var options = [(cell: Int, region: Int)]()
            var total = 0.0
            for cell in 0..<count where regions[cell] < 0 {
                let row = cell / size
                let column = cell % size
                var adjacent = [Int]()
                if row > 0 { adjacent.append(cell - size) }
                if row < size - 1 { adjacent.append(cell + size) }
                if column > 0 { adjacent.append(cell - 1) }
                if column < size - 1 { adjacent.append(cell + 1) }
                var seen = [Int]()
                for other in adjacent {
                    let region = regions[other]
                    if region >= 0, !seen.contains(region) {
                        seen.append(region)
                        options.append((cell, region))
                        total += weights[region]
                    }
                }
            }
            var pick = random.unit() * total
            var chosen = options[options.count - 1]
            for option in options {
                pick -= weights[option.region]
                if pick < 0 {
                    chosen = option
                    break
                }
            }
            regions[chosen.cell] = chosen.region
            remaining -= 1
        }
        return regions
    }
}
