import Foundation

struct DocumentExportArchive: Codable {
    struct ExportedDocument: Codable {
        let id: UUID
        let title: String
        let merchant: String
        let category: String
        let purchaseDate: Date?
        let expiryDate: Date?
        let renewalDate: Date?
        let notes: String
        let tags: [String]
        let ocrText: String
        let originalPDFFilename: String
        let pdfData: Data
        let thumbnailData: Data?
        let remindersEnabled: Bool
        let reminderLeadDays: Int
        let createdAt: Date
        let updatedAt: Date
        let paperlessStatus: String
        let paperlessTaskID: String?
        let lastPaperlessAttempt: Date?
    }

    let format: String
    let version: Int
    let exportedAt: Date
    let documents: [ExportedDocument]
}

enum DocumentExportService {
    static func makeArchive(for records: [DocumentRecord]) throws -> URL {
        let exported = try records.map { record in
            DocumentExportArchive.ExportedDocument(
                id: record.id,
                title: record.title,
                merchant: record.merchant,
                category: record.category.rawValue,
                purchaseDate: record.purchaseDate,
                expiryDate: record.expiryDate,
                renewalDate: record.renewalDate,
                notes: record.notes,
                tags: record.tags,
                ocrText: record.ocrText,
                originalPDFFilename: record.localPDFPath,
                pdfData: try DocumentFileStore.pdfData(forRelativePath: record.localPDFPath),
                thumbnailData: record.thumbnailData,
                remindersEnabled: record.remindersEnabled,
                reminderLeadDays: record.reminderLeadDays,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt,
                paperlessStatus: record.paperlessStatus.rawValue,
                paperlessTaskID: record.paperlessTaskID,
                lastPaperlessAttempt: record.lastPaperlessAttempt
            )
        }
        let archive = DocumentExportArchive(
            format: "DocKeeper portable document archive",
            version: 1,
            exportedAt: .now,
            documents: exported
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(archive)
        let name = "DocKeeper-Export-\(ISO8601DateFormatter().string(from: .now))-\(UUID().uuidString).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }
}
