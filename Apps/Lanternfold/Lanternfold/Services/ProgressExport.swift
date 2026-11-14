import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// A JSON copy of every saved puzzle, for the player's own backup.
struct ProgressDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]

    private struct Entry: Encodable {
        let key: String
        let kind: String
        let title: String
        let size: Int
        let difficulty: String
        let elapsedSeconds: Double
        let hintsUsed: Int
        let startedAt: Date
        let completedAt: Date?
        let solvedOnItsDay: Bool
        let regions: [Int]
        let stones: [String: Int]
        let marks: [Int]
    }

    private struct Payload: Encodable {
        let app: String
        let exportedAt: Date
        let puzzles: [Entry]
    }

    let data: Data

    @MainActor
    init(records: [PuzzleRecord]) throws {
        let entries = records.sorted { $0.startedAt < $1.startedAt }.map { record in
            let puzzle = record.puzzle
            var stones = [String: Int]()
            for (cell, clue) in puzzle?.stones ?? [:] {
                stones[String(cell)] = clue
            }
            return Entry(
                key: record.key,
                kind: record.kind,
                title: record.title,
                size: record.size,
                difficulty: record.difficulty.title,
                elapsedSeconds: record.elapsed,
                hintsUsed: record.hintsUsed,
                startedAt: record.startedAt,
                completedAt: record.completedAt,
                solvedOnItsDay: record.completedOnDay,
                regions: puzzle?.regions ?? [],
                stones: stones,
                marks: record.marksData.map { Int($0) }
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        data = try encoder.encode(Payload(app: "Lanternfold", exportedAt: .now, puzzles: entries))
    }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        data = contents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
