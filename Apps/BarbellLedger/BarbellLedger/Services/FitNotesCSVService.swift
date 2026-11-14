import CryptoKit
import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct CSVImportCollision: Identifiable {
    let rowNumber: Int
    let exerciseName: String
    let date: Date
    let occurrence: Int
    let pendingOccurrences: Int
    let existingOccurrences: Int

    var id: Int { rowNumber }
}

struct CSVImportReport {
    var workoutsCreated = 0
    var workoutsUpdated = 0
    var exercisesCreated = 0
    var setsImported = 0
    var newOccurrencesImported = 0
    var duplicatesSkipped = 0
    var timestampDuplicates = 0
    var collisionsImported = 0
    var pendingSetCount = 0
    var newSetCount = 0
    var wholeFileRepeated = false
    var collisions: [CSVImportCollision] = []
    var errors: [String] = []
    var warnings: [String] = []

    var requiresConfirmation: Bool { !collisions.isEmpty && pendingSetCount > 0 }
}

enum CSVCollisionPolicy {
    case ask
    case importAll
    case skip
}

enum CSVImportError: LocalizedError {
    case emptyFile
    case unclosedQuote
    case missingColumns([String])
    case noValidRows([String])

    var errorDescription: String? {
        switch self {
        case .emptyFile: "The selected CSV is empty."
        case .unclosedQuote: "The CSV contains an unclosed quoted field. Check the file around the last row and try again."
        case .missingColumns(let names): "The CSV is missing required columns: \(names.joined(separator: ", ")). Date and Exercise are required; the other FitNotes columns are optional."
        case .noValidRows(let errors): "No valid workout rows were found. \(errors.prefix(4).joined(separator: " "))"
        }
    }
}

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText, .text] }
    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        text = String(decoding: data, as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

struct FitNotesCSVService {
    private struct SetSignature: Hashable {
        let day: Date
        let exerciseName: String
        let weightKilograms: Double
        let reps: Int
        let distanceMeters: Double
        let durationSeconds: TimeInterval
        let comment: String
        let rpe: Double?
        let kind: SetKind
    }

    private struct RowGroupKey: Hashable {
        let signature: SetSignature
        let timestamp: Date?
    }

    private struct PendingRow {
        let rowNumber: Int
        let date: Date
        let timestamp: Date?
        let exerciseName: String
        let category: ExerciseCategory
        let weightKilograms: Double
        let reps: Int
        let distanceMeters: Double
        let durationSeconds: TimeInterval
        let comment: String
        let rpe: Double?
        let kind: SetKind
        let workoutNotes: String
        let signature: SetSignature
        let baseFingerprint: String
        let occurrence: Int
    }

    private struct ExistingRow {
        let signature: SetSignature
        let timestamp: Date?
    }

    private static let headers = ["Date", "Exercise", "Category", "Weight", "Weight Unit", "Reps", "Distance", "Distance Unit", "Time", "Comment", "RPE", "Set Type", "Workout Notes"]

    static func importCSV(_ text: String, defaultUnit: WeightUnit, context: ModelContext, collisionPolicy: CSVCollisionPolicy = .ask) throws -> CSVImportReport {
        var report = CSVImportReport()
        let rows = try parse(text)
        guard let headerRow = rows.first, rows.count > 1 else { throw CSVImportError.emptyFile }
        let columns = columnMap(headerRow)
        // Classic FitNotes exports name the column "Weight (kgs)" / "Weight (lbs)" with no Weight Unit column.
        let headerWeightUnit = columns["weight"].flatMap { impliedWeightUnit(forHeader: headerRow[$0]) }
        let missing = ["date", "exercise"].filter { columns[$0] == nil }.map { $0.capitalized }
        guard missing.isEmpty else { throw CSVImportError.missingColumns(missing) }

        var exercisesByName: [String: Exercise] = [:]
        for exercise in try context.fetch(FetchDescriptor<Exercise>()) {
            exercisesByName[exercise.name.foldingForImport] = exercise
        }

        let existingWorkouts = try context.fetch(FetchDescriptor<Workout>()).sorted { $0.startedAt < $1.startedAt }
        var workoutsByDay: [Date: Workout] = [:]
        var itemsByWorkoutAndExercise: [String: WorkoutExercise] = [:]
        var existingRows: [ExistingRow] = []
        var seenFingerprints = Set<String>()
        for workout in existingWorkouts {
            let day = Calendar.current.startOfDay(for: workout.startedAt)
            let hasImportedSets = workout.allSets.contains { !$0.importFingerprint.isEmpty }
            if hasImportedSets || !workout.importFileHashes.isEmpty {
                if workoutsByDay[day] == nil { workoutsByDay[day] = workout }
            }
            for item in workout.orderedExercises {
                itemsByWorkoutAndExercise[itemKey(workout: workout, exerciseName: item.exerciseName)] = item
                for set in item.orderedSets where !set.importFingerprint.isEmpty {
                    seenFingerprints.insert(set.importFingerprint)
                    let signature = makeSignature(day: day, exerciseName: item.exerciseName, weightKilograms: set.weightKilograms, reps: set.reps, distanceMeters: set.distanceMeters, durationSeconds: set.durationSeconds, comment: set.note, rpe: set.rpe, kind: set.kind)
                    existingRows.append(ExistingRow(signature: signature, timestamp: set.importTimestamp ?? inferredTimestamp(for: set, day: day)))
                }
            }
        }

        var pending: [PendingRow] = []
        var occurrences: [String: Int] = [:]
        for (offset, row) in rows.dropFirst().enumerated() {
            let rowNumber = offset + 2
            guard row.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { continue }
            do {
                let dateText = value("date", in: row, columns: columns)
                guard let parsedDate = parseDate(dateText) else { throw rowError("Unrecognized date ‘\(dateText)’. Use ISO yyyy-MM-dd or a common local date format.") }
                let date = parsedDate.date
                let timestamp = parsedDate.hasExplicitTime ? date : nil
                let exerciseName = value("exercise", in: row, columns: columns).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !exerciseName.isEmpty else { throw rowError("Exercise is blank.") }

                let weightText = value("weight", in: row, columns: columns)
                let weight = weightText.isEmpty ? 0 : NumberParsing.double(weightText)
                guard let weight, weight.isFinite, weight >= 0, weight <= 10_000_000 else { throw rowError("Weight ‘\(weightText)’ is not a valid non-negative number below 10,000,000.") }
                let unitText = value("weightunit", in: row, columns: columns)
                let weightUnit = try parseWeightUnit(unitText, fallback: headerWeightUnit ?? defaultUnit)
                let weightKilograms = weightUnit.toKilograms(weight)

                let repsText = value("reps", in: row, columns: columns)
                let repsValue = repsText.isEmpty ? 0 : NumberParsing.double(repsText)
                guard let repsValue, repsValue.isFinite, repsValue >= 0, repsValue <= 1_000_000, repsValue.rounded() == repsValue else { throw rowError("Reps ‘\(repsText)’ must be a non-negative whole number below 1,000,000.") }
                guard weight > 0 || repsValue > 0 || !value("distance", in: row, columns: columns).isEmpty || !value("time", in: row, columns: columns).isEmpty else {
                    throw rowError("The row has no weight, reps, distance, or time.")
                }

                let distanceText = value("distance", in: row, columns: columns)
                let distance = distanceText.isEmpty ? 0 : NumberParsing.double(distanceText)
                guard let distance, distance.isFinite, distance >= 0 else { throw rowError("Distance ‘\(distanceText)’ is not valid.") }
                let distanceUnit = try parseDistanceUnit(value("distanceunit", in: row, columns: columns))
                let distanceMeters = distance * distanceUnit

                let timeText = value("time", in: row, columns: columns)
                let duration = timeText.isEmpty ? 0 : NumberParsing.duration(timeText)
                guard let duration, duration.isFinite, duration >= 0 else { throw rowError("Time ‘\(timeText)’ is not valid. Use seconds, mm:ss, or hh:mm:ss.") }

                let rpeText = value("rpe", in: row, columns: columns)
                let rpe = rpeText.isEmpty ? nil : NumberParsing.double(rpeText)
                if rpeText.isEmpty == false {
                    guard let rpe, (0...10).contains(rpe) else { throw rowError("RPE ‘\(rpeText)’ must be between 0 and 10.") }
                }

                let category = ExerciseCategory.allCases.first { $0.rawValue.caseInsensitiveCompare(value("category", in: row, columns: columns).trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame } ?? .other
                let comment = value("comment", in: row, columns: columns).trimmingCharacters(in: .whitespacesAndNewlines)
                let kind = parseSetKind(value("settype", in: row, columns: columns))
                let day = Calendar.current.startOfDay(for: date)
                let signature = makeSignature(day: day, exerciseName: exerciseName, weightKilograms: weightKilograms, reps: Int(repsValue), distanceMeters: distanceMeters, durationSeconds: duration, comment: comment, rpe: rpe, kind: kind)
                let base = [
                    String((timestamp ?? day).timeIntervalSince1970), exerciseName.foldingForImport,
                    String(format: "%.5f", weightKilograms), String(Int(repsValue)),
                    String(format: "%.3f", distanceMeters), String(format: "%.3f", duration),
                    comment.foldingForImport, rpe?.cleanString ?? "", kind.rawValue
                ].joined(separator: "|")
                let occurrence = occurrences[base, default: 0]
                occurrences[base] = occurrence + 1
                pending.append(PendingRow(rowNumber: rowNumber, date: date, timestamp: timestamp, exerciseName: exerciseName, category: category, weightKilograms: weightKilograms, reps: Int(repsValue), distanceMeters: distanceMeters, durationSeconds: duration, comment: comment, rpe: rpe, kind: kind, workoutNotes: value("workoutnotes", in: row, columns: columns), signature: signature, baseFingerprint: base, occurrence: occurrence))
            } catch {
                report.errors.append("Row \(rowNumber): \(error.localizedDescription)")
            }
        }

        if pending.isEmpty, !report.errors.isEmpty { throw CSVImportError.noValidRows(report.errors) }
        if pending.isEmpty { throw CSVImportError.emptyFile }

        let fileHash = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        let requiredDays = Set(pending.map(\.signature.day))
        let previouslyHashedDays = Set(existingWorkouts.filter { $0.importFileHashes.contains(fileHash) }.map { Calendar.current.startOfDay(for: $0.startedAt) })
        if requiredDays.allSatisfy({ previouslyHashedDays.contains($0) }) {
            report.wholeFileRepeated = true
            report.duplicatesSkipped = pending.count
            report.warnings.append("This exact file was already imported. No rows were written.")
            return report
        }

        var existingGroupCounts: [RowGroupKey: Int] = [:]
        var existingTotalsBySignature: [SetSignature: Int] = [:]
        for row in existingRows {
            let key = RowGroupKey(signature: row.signature, timestamp: row.timestamp)
            existingGroupCounts[key, default: 0] += 1
            existingTotalsBySignature[row.signature, default: 0] += 1
        }
        var pendingTotals: [RowGroupKey: Int] = [:]
        for row in pending {
            pendingTotals[RowGroupKey(signature: row.signature, timestamp: row.timestamp), default: 0] += 1
        }

        var pendingOccurrences: [RowGroupKey: Int] = [:]
        var newRowNumbers = Set<Int>()
        var collisionsByRow: [Int: CSVImportCollision] = [:]
        var timestampDuplicateCount = 0
        let rowsInMatchingOrder = pending.filter { $0.timestamp != nil } + pending.filter { $0.timestamp == nil }
        for row in rowsInMatchingOrder {
            let key = RowGroupKey(signature: row.signature, timestamp: row.timestamp)
            let occurrence = pendingOccurrences[key, default: 0] + 1
            pendingOccurrences[key] = occurrence

            let matchedKey: RowGroupKey?
            if row.timestamp != nil {
                matchedKey = (existingGroupCounts[key] ?? 0) > 0 ? key : nil
            } else {
                matchedKey = existingGroupCounts.keys.filter { candidate in
                    candidate.signature == row.signature && (existingGroupCounts[candidate] ?? 0) > 0
                }.sorted { lhs, rhs in
                    switch (lhs.timestamp, rhs.timestamp) {
                    case (nil, nil): return false
                    case (nil, _): return true
                    case (_, nil): return false
                    case (let lhsDate?, let rhsDate?): return lhsDate < rhsDate
                    }
                }.first
            }

            guard let matchedKey else {
                newRowNumbers.insert(row.rowNumber)
                continue
            }
            existingGroupCounts[matchedKey] = (existingGroupCounts[matchedKey] ?? 0) - 1
            if row.timestamp == nil {
                collisionsByRow[row.rowNumber] = CSVImportCollision(
                    rowNumber: row.rowNumber,
                    exerciseName: row.exerciseName,
                    date: row.date,
                    occurrence: occurrence,
                    pendingOccurrences: pendingTotals[key] ?? occurrence,
                    existingOccurrences: existingTotalsBySignature[row.signature] ?? 0
                )
            } else {
                timestampDuplicateCount += 1
            }
        }

        report.newSetCount = newRowNumbers.count
        report.timestampDuplicates = timestampDuplicateCount
        if !collisionsByRow.isEmpty, collisionPolicy == .ask {
            report.collisions = collisionsByRow.values.sorted { $0.rowNumber < $1.rowNumber }
            report.pendingSetCount = pending.count
            return report
        }

        let rowsToImport = pending.filter { row in
            newRowNumbers.contains(row.rowNumber) || (collisionPolicy == .importAll && collisionsByRow[row.rowNumber] != nil)
        }
        report.duplicatesSkipped = timestampDuplicateCount
        if collisionPolicy == .skip {
            report.duplicatesSkipped += collisionsByRow.count
            if collisionsByRow.count > 0 { report.warnings.append("\(collisionsByRow.count == 1 ? "1 reviewed existing occurrence was" : "\(collisionsByRow.count) reviewed existing occurrences were") skipped; only occurrences beyond the existing count were imported.") }
        } else if collisionPolicy == .importAll {
            report.collisionsImported = collisionsByRow.count
            if collisionsByRow.count > 0 { report.warnings.append("\(collisionsByRow.count == 1 ? "1 reviewed date-only occurrence was" : "\(collisionsByRow.count) reviewed date-only occurrences were") imported again as additional same-day sets.") }
        }
        if timestampDuplicateCount > 0 { report.warnings.append("\(timestampDuplicateCount == 1 ? "1 exact-timestamp duplicate occurrence was" : "\(timestampDuplicateCount) exact-timestamp duplicate occurrences were") skipped.") }
        report.collisions = []
        let recordsWholeFile = collisionsByRow.isEmpty || collisionPolicy == .importAll

        var touchedWorkouts: [UUID: Workout] = [:]
        var newWorkoutIDs = Set<UUID>()
        for row in rowsToImport {
            let day = Calendar.current.startOfDay(for: row.date)
            let workout: Workout
            if let existing = workoutsByDay[day] {
                workout = existing
                if touchedWorkouts[workout.id] == nil && !newWorkoutIDs.contains(workout.id) { report.workoutsUpdated += 1 }
                workout.startedAt = min(workout.startedAt, row.date)
                workout.completedAt = max(workout.completedAt ?? row.date, row.date)
                if workout.notes.isEmpty { workout.notes = row.workoutNotes }
            } else {
                workout = Workout(name: "Imported · \(day.mediumDay)", startedAt: row.date)
                workout.completedAt = row.date
                workout.notes = row.workoutNotes
                context.insert(workout)
                workoutsByDay[day] = workout
                newWorkoutIDs.insert(workout.id)
                report.workoutsCreated += 1
            }
            touchedWorkouts[workout.id] = workout

            let exerciseKey = row.exerciseName.foldingForImport
            let exercise: Exercise
            if let existing = exercisesByName[exerciseKey] {
                exercise = existing
            } else {
                exercise = Exercise(name: row.exerciseName, category: row.category)
                context.insert(exercise)
                exercisesByName[exerciseKey] = exercise
                report.exercisesCreated += 1
            }

            let key = itemKey(workout: workout, exerciseName: row.exerciseName)
            let item: WorkoutExercise
            if let existing = itemsByWorkoutAndExercise[key] {
                item = existing
                if item.exercise == nil { item.exercise = exercise }
            } else {
                item = WorkoutExercise(exercise: exercise, order: workout.orderedExercises.count)
                workout.exercises?.append(item)
                itemsByWorkoutAndExercise[key] = item
            }
            let set = WorkoutSet(order: item.orderedSets.count, weightKilograms: row.weightKilograms, reps: row.reps, rpe: row.rpe, kind: row.kind)
            set.note = row.comment
            set.distanceMeters = row.distanceMeters
            set.durationSeconds = row.durationSeconds
            set.isCompleted = true
            set.completedAt = row.date
            set.importTimestamp = row.timestamp
            set.importFingerprint = uniqueFingerprint(for: row, seen: &seenFingerprints)
            item.sets?.append(set)
            report.setsImported += 1
            if newRowNumbers.contains(row.rowNumber) { report.newOccurrencesImported += 1 }
        }

        for workout in touchedWorkouts.values {
            for (itemIndex, item) in workout.orderedExercises.enumerated() {
                item.order = itemIndex
                for (setIndex, set) in item.orderedSets.enumerated() { set.order = setIndex }
            }
        }
        if recordsWholeFile {
            for day in requiredDays {
                guard let workout = workoutsByDay[day], !workout.importFileHashes.contains(fileHash) else { continue }
                workout.importFileHashes.append(fileHash)
            }
        }
        if report.setsImported > 0 || recordsWholeFile { try context.save() }
        return report
    }

    private static func itemKey(workout: Workout, exerciseName: String) -> String {
        "\(workout.id.uuidString)-\(exerciseName.foldingForImport)"
    }

    private static func makeSignature(day: Date, exerciseName: String, weightKilograms: Double, reps: Int, distanceMeters: Double, durationSeconds: TimeInterval, comment: String, rpe: Double?, kind: SetKind) -> SetSignature {
        SetSignature(
            day: day,
            exerciseName: exerciseName.foldingForImport,
            weightKilograms: (weightKilograms * 100_000).rounded() / 100_000,
            reps: reps,
            distanceMeters: (distanceMeters * 1_000).rounded() / 1_000,
            durationSeconds: (durationSeconds * 1_000).rounded() / 1_000,
            comment: comment.foldingForImport,
            rpe: rpe,
            kind: kind
        )
    }

    private static func inferredTimestamp(for set: WorkoutSet, day: Date) -> Date? {
        guard let completedAt = set.completedAt, abs(completedAt.timeIntervalSince(day)) > 0.001 else { return nil }
        return completedAt
    }

    private static func uniqueFingerprint(for row: PendingRow, seen: inout Set<String>) -> String {
        var occurrence = row.occurrence
        var candidate = "\(row.baseFingerprint)|\(occurrence)"
        while seen.contains(candidate) {
            occurrence += 1
            candidate = "\(row.baseFingerprint)|\(occurrence)"
        }
        seen.insert(candidate)
        return candidate
    }

    static func export(workouts: [Workout], unit: WeightUnit) -> String {
        var lines = [headers.map(csvEscape).joined(separator: ",")]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        let completed = workouts.filter { $0.completedAt != nil }.sorted { $0.startedAt < $1.startedAt }
        for workout in completed {
            for item in workout.orderedExercises {
                for set in item.orderedSets where set.isCompleted {
                    let date = set.completedAt ?? workout.startedAt
                    let day = Calendar.current.startOfDay(for: date)
                    let hasTimestamp = set.importTimestamp != nil || abs(date.timeIntervalSince(day)) > 0.001
                    formatter.dateFormat = hasTimestamp ? "yyyy-MM-dd HH:mm:ss" : "yyyy-MM-dd"
                    let fields = [
                        formatter.string(from: date),
                        item.exerciseName,
                        item.exercise?.category.rawValue ?? ExerciseCategory.other.rawValue,
                        unit.fromKilograms(set.weightKilograms).cleanString,
                        unit.label,
                        String(set.reps),
                        set.distanceMeters.cleanString,
                        "m",
                        set.durationSeconds.cleanString,
                        set.note,
                        set.rpe?.cleanString ?? "",
                        set.kind.rawValue,
                        workout.notes
                    ]
                    lines.append(fields.map(csvEscape).joined(separator: ","))
                }
            }
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    private static func parse(_ input: String) throws -> [[String]] {
        let text = input.hasPrefix("\u{FEFF}") ? String(input.dropFirst()) : input
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CSVImportError.emptyFile }
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            if character == "\"" {
                if quoted, next < text.endIndex, text[next] == "\"" {
                    field.append("\"")
                    index = text.index(after: next)
                    continue
                }
                quoted.toggle()
            } else if character == ",", !quoted {
                row.append(field)
                field = ""
            } else if (character == "\n" || character == "\r" || character == "\r\n"), !quoted {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
                if character == "\r", next < text.endIndex, text[next] == "\n" { index = text.index(after: next); continue }
            } else {
                field.append(character)
            }
            index = next
        }
        guard !quoted else { throw CSVImportError.unclosedQuote }
        row.append(field)
        rows.append(row)
        return rows.filter { $0.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
    }

    private static func columnMap(_ row: [String]) -> [String: Int] {
        let aliases: [String: [String]] = [
            "date": ["date", "workoutdate", "day"],
            "exercise": ["exercise", "exercisename", "movement"],
            "category": ["category", "exercisecategory", "muscle", "musclegroup"],
            "weight": ["weight", "load", "weightvalue", "weightkg", "weightkgs", "weightkilograms", "weightlb", "weightlbs", "weightpounds"],
            "weightunit": ["weightunit", "weightunits", "unit", "units"],
            "reps": ["reps", "repetitions", "repetitioncount"],
            "distance": ["distance", "distancevalue"],
            "distanceunit": ["distanceunit", "distanceunits"],
            "time": ["time", "duration", "elapsedtime"],
            "comment": ["comment", "comments", "note", "notes", "setnotes"],
            "rpe": ["rpe", "ratingofperceivedexertion"],
            "settype": ["settype", "type"],
            "workoutnotes": ["workoutnotes", "sessionnotes"]
        ]
        var result: [String: Int] = [:]
        for (index, header) in row.enumerated() {
            let normalized = header.normalizedHeader
            for (key, names) in aliases where names.contains(normalized) && result[key] == nil { result[key] = index }
        }
        return result
    }

    private static func impliedWeightUnit(forHeader header: String) -> WeightUnit? {
        switch header.normalizedHeader {
        case "weightkg", "weightkgs", "weightkilograms": .kilograms
        case "weightlb", "weightlbs", "weightpounds": .pounds
        default: nil
        }
    }

    private static func value(_ key: String, in row: [String], columns: [String: Int]) -> String {
        guard let index = columns[key], row.indices.contains(index) else { return "" }
        return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseDate(_ text: String) -> (date: Date, hasExplicitTime: Bool)? {
        guard !text.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: text) { return (date, true) }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: text) { return (date, true) }
        let formats: [(format: String, hasTime: Bool)] = [
            ("yyyy-MM-dd HH:mm:ss", true),
            ("yyyy-MM-dd HH:mm", true),
            ("dd/MM/yyyy HH:mm", true),
            ("MM/dd/yyyy HH:mm", true),
            ("yyyy-MM-dd", false),
            ("yyyy/MM/dd", false),
            ("dd/MM/yyyy", false),
            ("MM/dd/yyyy", false),
            ("d MMM yyyy", false),
            ("dd MMM yyyy", false),
            ("MMM d, yyyy", false),
            ("dd.MM.yyyy", false)
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.isLenient = false
        for format in formats {
            formatter.dateFormat = format.format
            if let date = formatter.date(from: text) { return (date, format.hasTime) }
        }
        return nil
    }

    private static func parseWeightUnit(_ text: String, fallback: WeightUnit) throws -> WeightUnit {
        switch text.normalizedHeader {
        case "": fallback
        case "kg", "kgs", "kilogram", "kilograms", "kilo", "kilos": .kilograms
        case "lb", "lbs", "pound", "pounds": .pounds
        case "bw", "bodyweight": .kilograms
        default: throw rowError("Weight unit ‘\(text)’ is not recognized. Use kg or lb.")
        }
    }

    private static func parseDistanceUnit(_ text: String) throws -> Double {
        switch text.normalizedHeader {
        case "", "m", "meter", "meters", "metre", "metres": 1
        case "km", "kilometer", "kilometers", "kilometre", "kilometres": 1_000
        case "mi", "mile", "miles": 1_609.344
        case "ft", "foot", "feet": 0.3048
        case "yd", "yard", "yards": 0.9144
        default: throw rowError("Distance unit ‘\(text)’ is not recognized.")
        }
    }

    private static func parseSetKind(_ text: String) -> SetKind {
        switch text.normalizedHeader {
        case "warmup", "warmupset": .warmup
        case "drop", "dropset": .drop
        case "failure", "fail", "failureset": .failure
        default: .working
        }
    }

    private static func rowError(_ message: String) -> NSError {
        NSError(domain: "BarbellLedger.CSVRow", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}

private extension String {
    var normalizedHeader: String {
        lowercased().filter { $0.isLetter || $0.isNumber }
    }

    var foldingForImport: String {
        trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}
