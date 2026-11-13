import Foundation

struct DocumentDraft: Identifiable, Hashable {
    let id: UUID
    let localPDFPath: String
    let suggestedTitle: String
    let thumbnailData: Data?
    let ocrText: String
    let processingWarning: String?

    init(
        id: UUID = UUID(),
        localPDFPath: String,
        suggestedTitle: String,
        thumbnailData: Data?,
        ocrText: String,
        processingWarning: String? = nil
    ) {
        self.id = id
        self.localPDFPath = localPDFPath
        self.suggestedTitle = suggestedTitle
        self.thumbnailData = thumbnailData
        self.ocrText = ocrText
        self.processingWarning = processingWarning
    }
}
