import Foundation

struct ReportSnapshot {
    let title: String
    let customerName: String
    let customerContact: String
    let siteAddress: String
    let inspectorName: String
    let companyName: String
    let companyDetails: String
    let reportNotes: String
    let inspectionDate: Date
    let generatedAt: Date
    let findings: [FindingSnapshot]

    @MainActor
    init(project: InspectionProject) {
        title = project.title.trimmingCharacters(in: .whitespacesAndNewlines)
        customerName = project.customerName.trimmingCharacters(in: .whitespacesAndNewlines)
        customerContact = project.customerContact.trimmingCharacters(in: .whitespacesAndNewlines)
        siteAddress = project.siteAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        inspectorName = project.inspectorName.trimmingCharacters(in: .whitespacesAndNewlines)
        companyName = project.companyName.trimmingCharacters(in: .whitespacesAndNewlines)
        companyDetails = project.companyDetails.trimmingCharacters(in: .whitespacesAndNewlines)
        reportNotes = project.reportNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        inspectionDate = project.inspectionDate
        generatedAt = .now
        findings = project.sortedFindings.map(FindingSnapshot.init)
    }
}

struct FindingSnapshot {
    let title: String
    let category: String
    let severity: String
    let severityDescription: String
    let notes: String
    let recommendation: String
    let transcript: String
    let audioDuration: TimeInterval?
    let createdAt: Date
    let photos: [PhotoSnapshot]

    @MainActor
    init(finding: Finding) {
        title = finding.title.trimmingCharacters(in: .whitespacesAndNewlines)
        category = finding.category.rawValue
        severity = finding.severity.rawValue
        severityDescription = finding.severity.reportDescription
        notes = finding.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        recommendation = finding.recommendation.trimmingCharacters(in: .whitespacesAndNewlines)
        transcript = finding.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        audioDuration = finding.audioFileName == nil ? nil : finding.audioDuration
        createdAt = finding.createdAt
        photos = finding.sortedPhotos.map(PhotoSnapshot.init)
    }
}

struct PhotoSnapshot {
    let fileName: String
    let caption: String

    @MainActor
    init(photo: FindingPhoto) {
        fileName = photo.fileName
        caption = photo.caption.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
