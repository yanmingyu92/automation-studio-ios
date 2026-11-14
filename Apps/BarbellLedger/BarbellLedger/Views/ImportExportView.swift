import SwiftData
import SwiftUI
import UniformTypeIdentifiers

private struct PendingCSVImport {
    let text: String
    let defaultUnit: WeightUnit
    let report: CSVImportReport
}

struct ImportExportView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("defaultWeightUnit") private var unit: WeightUnit = .kilograms
    @State private var showingImporter = false
    @State private var exportDocument: CSVDocument?
    @State private var report: CSVImportReport?
    @State private var pendingImport: PendingCSVImport?
    @State private var errorMessage: String?
    @State private var isProcessing = false

    var body: some View {
        Form {
            Section("FitNotes migration") {
                Label("Choose your FitNotes CSV export. BarbellLedger reads it only when you select it and saves valid rows locally.", systemImage: "doc.badge.arrow.up")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Import FitNotes CSV", systemImage: "square.and.arrow.down") { showingImporter = true }
                    .disabled(isProcessing)
                Text("Date and Exercise are required. Rows are grouped into imported workouts by local calendar day. Exact file repeats are skipped; ambiguous same-day rows always require your confirmation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Full export") {
                Label("Export completed sets with FitNotes-compatible fields plus RPE, set type, and workout notes. Available timestamps are preserved. Active workouts are excluded.", systemImage: "lock.shield")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Export All Workout History", systemImage: "square.and.arrow.up", action: export)
                    .disabled(isProcessing)
            }

            if isProcessing {
                Section { HStack { ProgressView(); Text("Processing CSV…") } }
            }

            if let pendingImport {
                Section("Import Confirmation Required") {
                    Label("\(pendingImport.report.collisions.count == 1 ? "1 file occurrence is" : "\(pendingImport.report.collisions.count) file occurrences are") covered by existing date-only sets. They may be repeated export rows or a separate same-day session. Nothing has been imported from this file yet.", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    LabeledContent("Valid rows in file", value: "\(pendingImport.report.pendingSetCount)")
                    LabeledContent("New occurrences beyond existing sets", value: "\(pendingImport.report.newSetCount)")
                    if pendingImport.report.timestampDuplicates > 0 {
                        LabeledContent("Exact-timestamp duplicates", value: "\(pendingImport.report.timestampDuplicates)")
                    }
                    NavigationLink("Review Existing Occurrences") {
                        CSVCollisionList(collisions: pendingImport.report.collisions)
                    }
                    Button("Import Reviewed Rows as Additional Sets") {
                        performImport(pendingImport.text, defaultUnit: pendingImport.defaultUnit, collisionPolicy: .importAll)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint("Re-imports every reviewed occurrence as additional sets in its local-day workout and adds all new occurrences. Exact-timestamp duplicates remain skipped.")
                    if pendingImport.report.newSetCount > 0 {
                        Button("Import Only \(pendingImport.report.newSetCount.counted("New Occurrence"))") {
                            performImport(pendingImport.text, defaultUnit: pendingImport.defaultUnit, collisionPolicy: .skip)
                        }
                        .accessibilityHint("Skips reviewed existing occurrences and imports only pending occurrences beyond the existing count")
                    }
                    Button("Cancel Import", role: .cancel) { self.pendingImport = nil }
                    if !pendingImport.report.errors.isEmpty {
                        NavigationLink("Review \(pendingImport.report.errors.count.counted("row error"))") {
                            CSVErrorList(errors: pendingImport.report.errors)
                        }
                    }
                }
            }

            if let report {
                Section("Last Import") {
                    if report.wholeFileRepeated {
                        Label("This exact file was already imported. No changes were made.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    LabeledContent("Workouts created", value: "\(report.workoutsCreated)")
                    LabeledContent("Existing workouts updated", value: "\(report.workoutsUpdated)")
                    LabeledContent("New exercises", value: "\(report.exercisesCreated)")
                    LabeledContent("Sets imported", value: "\(report.setsImported)")
                    LabeledContent("New occurrences imported", value: "\(report.newOccurrencesImported)")
                    if report.collisionsImported > 0 {
                        LabeledContent("Reviewed occurrences re-imported", value: "\(report.collisionsImported)")
                    }
                    if report.timestampDuplicates > 0 {
                        LabeledContent("Exact-timestamp duplicates skipped", value: "\(report.timestampDuplicates)")
                    }
                    if report.duplicatesSkipped > 0 {
                        LabeledContent("Total rows skipped", value: "\(report.duplicatesSkipped)")
                    }
                    if !report.warnings.isEmpty {
                        ForEach(report.warnings, id: \.self) { Text($0).font(.footnote).foregroundStyle(.secondary) }
                    }
                    if !report.errors.isEmpty {
                        NavigationLink("Review \(report.errors.count.counted("row error"))") { CSVErrorList(errors: report.errors) }
                    }
                }
            }
        }
        .navigationTitle("Import & Export")
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.commaSeparatedText, .text], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                importFile(url)
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
        .fileExporter(isPresented: Binding(get: { exportDocument != nil }, set: { if !$0 { exportDocument = nil } }), document: exportDocument, contentType: .commaSeparatedText, defaultFilename: "BarbellLedger-\(Date().formatted(.iso8601.year().month().day()))") { result in
            if case .failure(let error) = result { errorMessage = error.localizedDescription }
            exportDocument = nil
        }
        .alert("CSV Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func importFile(_ url: URL) {
        report = nil
        pendingImport = nil
        errorMessage = nil
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
                throw CocoaError(.fileReadInapplicableStringEncoding)
            }
            performImport(text, defaultUnit: unit, collisionPolicy: .ask)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performImport(_ text: String, defaultUnit: WeightUnit, collisionPolicy: CSVCollisionPolicy) {
        isProcessing = true
        defer { isProcessing = false }
        do {
            let result = try FitNotesCSVService.importCSV(text, defaultUnit: defaultUnit, context: modelContext, collisionPolicy: collisionPolicy)
            if result.requiresConfirmation {
                pendingImport = PendingCSVImport(text: text, defaultUnit: defaultUnit, report: result)
                report = nil
            } else {
                pendingImport = nil
                report = result
            }
        } catch {
            pendingImport = nil
            errorMessage = error.localizedDescription
        }
    }

    private func export() {
        do {
            let workouts = try modelContext.fetch(FetchDescriptor<Workout>(sortBy: [SortDescriptor(\.startedAt)]))
            exportDocument = CSVDocument(text: FitNotesCSVService.export(workouts: workouts, unit: unit))
        } catch { errorMessage = error.localizedDescription }
    }
}

struct CSVCollisionList: View {
    let collisions: [CSVImportCollision]

    var body: some View {
        List(collisions) { collision in
            VStack(alignment: .leading, spacing: 6) {
                Text("Row \(collision.rowNumber) · \(collision.exerciseName)")
                    .font(.headline)
                Text("\(collision.date.mediumDay) · file occurrence \(collision.occurrence) of \(collision.pendingOccurrences)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(collision.existingOccurrences) existing imported \(collision.existingOccurrences == 1 ? "occurrence has" : "occurrences have") these values on this local day. This file occurrence is within that existing count. Import it again only if it belongs to a separate same-day session.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .textSelection(.enabled)
            .accessibilityElement(children: .combine)
        }
        .navigationTitle("Row Collisions")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CSVErrorList: View {
    let errors: [String]

    var body: some View {
        List(errors, id: \.self) { error in
            Label(error, systemImage: "exclamationmark.triangle")
                .textSelection(.enabled)
        }
        .navigationTitle("Row Errors")
        .navigationBarTitleDisplayMode(.inline)
    }
}
