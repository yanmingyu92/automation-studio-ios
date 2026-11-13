import Foundation
import SwiftData

enum DocumentCategory: String, Codable, CaseIterable, Identifiable {
    case receipt
    case contract
    case warranty
    case statement
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .receipt: "Receipt"
        case .contract: "Contract"
        case .warranty: "Warranty"
        case .statement: "Statement"
        case .other: "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .receipt: "receipt"
        case .contract: "doc.text"
        case .warranty: "checkmark.shield"
        case .statement: "list.bullet.rectangle"
        case .other: "doc"
        }
    }
}

enum PaperlessSyncStatus: String, Codable {
    case notSynced
    case uploading
    case accepted
    case failed

    var title: String {
        switch self {
        case .notSynced: "Not uploaded"
        case .uploading: "Uploading"
        case .accepted: "Accepted for processing"
        case .failed: "Upload failed"
        }
    }
}

@Model
final class DocumentRecord {
    @Attribute(.unique) var id: UUID
    var title: String
    var merchant: String
    var categoryRawValue: String
    var purchaseDate: Date?
    var expiryDate: Date?
    var renewalDate: Date?
    var notes: String
    var tags: [String]
    var ocrText: String
    var localPDFPath: String
    var thumbnailData: Data?
    var remindersEnabled: Bool
    var reminderLeadDays: Int
    var createdAt: Date
    var updatedAt: Date
    var paperlessTaskID: String?
    var paperlessStatusRawValue: String
    var lastPaperlessAttempt: Date?
    var lastPaperlessError: String?

    init(
        id: UUID = UUID(),
        title: String,
        merchant: String = "",
        category: DocumentCategory = .other,
        purchaseDate: Date? = nil,
        expiryDate: Date? = nil,
        renewalDate: Date? = nil,
        notes: String = "",
        tags: [String] = [],
        ocrText: String = "",
        localPDFPath: String,
        thumbnailData: Data? = nil,
        remindersEnabled: Bool = false,
        reminderLeadDays: Int = 7,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        paperlessTaskID: String? = nil,
        paperlessStatus: PaperlessSyncStatus = .notSynced,
        lastPaperlessAttempt: Date? = nil,
        lastPaperlessError: String? = nil
    ) {
        self.id = id
        self.title = title
        self.merchant = merchant
        self.categoryRawValue = category.rawValue
        self.purchaseDate = purchaseDate
        self.expiryDate = expiryDate
        self.renewalDate = renewalDate
        self.notes = notes
        self.tags = tags
        self.ocrText = ocrText
        self.localPDFPath = localPDFPath
        self.thumbnailData = thumbnailData
        self.remindersEnabled = remindersEnabled
        self.reminderLeadDays = reminderLeadDays
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.paperlessTaskID = paperlessTaskID
        self.paperlessStatusRawValue = paperlessStatus.rawValue
        self.lastPaperlessAttempt = lastPaperlessAttempt
        self.lastPaperlessError = lastPaperlessError
    }

    var category: DocumentCategory {
        get { DocumentCategory(rawValue: categoryRawValue) ?? .other }
        set { categoryRawValue = newValue.rawValue }
    }

    var paperlessStatus: PaperlessSyncStatus {
        get { PaperlessSyncStatus(rawValue: paperlessStatusRawValue) ?? .notSynced }
        set { paperlessStatusRawValue = newValue.rawValue }
    }

    var searchableText: String {
        ([title, merchant, notes, ocrText] + tags).joined(separator: " ")
    }
}
