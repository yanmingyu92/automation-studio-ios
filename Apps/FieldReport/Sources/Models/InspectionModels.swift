import Foundation
import SwiftData

@Model
final class InspectionProject {
    var id: UUID
    var title: String
    var customerName: String
    var customerContact: String
    var siteAddress: String
    var inspectorName: String
    var companyName: String
    var companyDetails: String
    var reportNotes: String
    var inspectionDate: Date
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Finding.project)
    var findings: [Finding] = []

    init(
        title: String,
        customerName: String = "",
        customerContact: String = "",
        siteAddress: String = "",
        inspectorName: String = "",
        companyName: String = "",
        companyDetails: String = "",
        reportNotes: String = "",
        inspectionDate: Date = .now,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = UUID()
        self.title = title
        self.customerName = customerName
        self.customerContact = customerContact
        self.siteAddress = siteAddress
        self.inspectorName = inspectorName
        self.companyName = companyName
        self.companyDetails = companyDetails
        self.reportNotes = reportNotes
        self.inspectionDate = inspectionDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var sortedFindings: [Finding] {
        findings.sorted { lhs, rhs in
            if lhs.sortOrder == rhs.sortOrder {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.sortOrder < rhs.sortOrder
        }
    }
}

@Model
final class Finding {
    var id: UUID
    var title: String
    var categoryRaw: String
    var severityRaw: String
    var notes: String
    var recommendation: String
    var transcript: String
    var audioFileName: String?
    var audioDuration: TimeInterval
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
    var project: InspectionProject?

    @Relationship(deleteRule: .cascade, inverse: \FindingPhoto.finding)
    var photos: [FindingPhoto] = []

    init(
        title: String = "",
        category: IssueCategory = .general,
        severity: Severity = .medium,
        notes: String = "",
        recommendation: String = "",
        transcript: String = "",
        audioFileName: String? = nil,
        audioDuration: TimeInterval = 0,
        sortOrder: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = UUID()
        self.title = title
        self.categoryRaw = category.rawValue
        self.severityRaw = severity.rawValue
        self.notes = notes
        self.recommendation = recommendation
        self.transcript = transcript
        self.audioFileName = audioFileName
        self.audioDuration = audioDuration
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var category: IssueCategory {
        get { IssueCategory(rawValue: categoryRaw) ?? .general }
        set { categoryRaw = newValue.rawValue }
    }

    var severity: Severity {
        get { Severity(rawValue: severityRaw) ?? .medium }
        set { severityRaw = newValue.rawValue }
    }

    var sortedPhotos: [FindingPhoto] {
        photos.sorted { $0.createdAt < $1.createdAt }
    }
}

@Model
final class FindingPhoto {
    var id: UUID
    var fileName: String
    var thumbnailFileName: String
    var caption: String
    var createdAt: Date
    var finding: Finding?

    init(fileName: String, thumbnailFileName: String, caption: String = "", createdAt: Date = .now) {
        self.id = UUID()
        self.fileName = fileName
        self.thumbnailFileName = thumbnailFileName
        self.caption = caption
        self.createdAt = createdAt
    }
}

enum IssueCategory: String, CaseIterable, Codable, Identifiable {
    case general = "General"
    case roofing = "Roofing"
    case electrical = "Electrical"
    case plumbing = "Plumbing"
    case hvac = "HVAC"
    case structure = "Structure"
    case exterior = "Exterior"
    case interior = "Interior"
    case moisture = "Moisture"
    case safety = "Safety"
    case appliances = "Appliances"
    case site = "Site & drainage"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .general: "doc.text.magnifyingglass"
        case .roofing: "house.lodge"
        case .electrical: "bolt.trianglebadge.exclamationmark"
        case .plumbing: "drop.triangle"
        case .hvac: "wind"
        case .structure: "building.2"
        case .exterior: "fence"
        case .interior: "door.left.hand.open"
        case .moisture: "humidity"
        case .safety: "exclamationmark.shield"
        case .appliances: "washer"
        case .site: "arrow.down.to.line.compact"
        }
    }
}

enum Severity: String, CaseIterable, Codable, Identifiable {
    case observation = "Observation"
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case urgent = "Urgent"

    var id: String { rawValue }

    var reportDescription: String {
        switch self {
        case .observation: "Documented for awareness"
        case .low: "Monitor or address during routine maintenance"
        case .medium: "Repair or further evaluation recommended"
        case .high: "Prompt attention recommended"
        case .urgent: "Immediate attention recommended"
        }
    }
}
