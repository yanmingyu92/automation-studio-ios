import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
final class DocumentImportController: ObservableObject {
    @Published private(set) var isProcessing = false
    @Published private(set) var processingMessage = "Preparing document…"
    @Published var draft: DocumentDraft?
    @Published var errorMessage: String?

    private let ocrService = VisionOCRService()

    func importScannedPages(_ pages: [UIImage]) async {
        do {
            processingMessage = "Building your PDF…"
            let data = try DocumentFileStore.makePDF(from: pages)
            let title = "Scanned document \(Self.scanDateFormatter.string(from: .now))"
            await process(pdfData: data, suggestedTitle: title)
        } catch {
            present(error)
        }
    }

    func importPhoto(data: Data) async {
        guard let image = UIImage(data: data) else {
            errorMessage = DocumentFileStoreError.invalidImage.localizedDescription
            return
        }
        do {
            processingMessage = "Converting your photo to PDF…"
            let pdfData = try DocumentFileStore.makePDF(from: [image])
            await process(pdfData: pdfData, suggestedTitle: "Imported photo")
        } catch {
            present(error)
        }
    }

    func importFile(at url: URL) async {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }

        do {
            processingMessage = "Reading your document…"
            // Read off the main actor so a large or slow (network/iCloud) file cannot freeze the UI.
            let data = try await Task.detached(priority: .userInitiated) {
                try Data(contentsOf: url)
            }.value
            try Task.checkCancellation()
            let type = UTType(filenameExtension: url.pathExtension.lowercased())
            if type?.conforms(to: .pdf) == true {
                await process(
                    pdfData: data,
                    suggestedTitle: url.deletingPathExtension().lastPathComponent
                )
            } else if type?.conforms(to: .image) == true, let image = UIImage(data: data) {
                let pdfData = try DocumentFileStore.makePDF(from: [image])
                await process(
                    pdfData: pdfData,
                    suggestedTitle: url.deletingPathExtension().lastPathComponent
                )
            } else {
                throw DocumentFileStoreError.invalidPDF
            }
        } catch {
            present(error)
        }
    }

    private func process(pdfData: Data, suggestedTitle: String) async {
        guard !isProcessing else { return }
        isProcessing = true
        processingMessage = "Saving a private local copy…"
        defer { isProcessing = false }

        var savedPath: String?
        do {
            try Task.checkCancellation()
            let path = try DocumentFileStore.savePDF(pdfData)
            savedPath = path
            DocumentFileStore.registerDraftPDF(path)
            let thumbnail = DocumentFileStore.thumbnail(forPDFData: pdfData)

            processingMessage = "Recognizing text on this device…"
            var text = ""
            var warning: String?
            do {
                text = try await ocrService.recognizeText(inPDFData: pdfData)
                if text.isEmpty {
                    warning = "No selectable text was found. You can still search the details you add."
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                warning = "Text recognition could not finish: \(error.localizedDescription)"
            }

            try Task.checkCancellation()
            draft = DocumentDraft(
                localPDFPath: path,
                suggestedTitle: suggestedTitle.isEmpty ? "Untitled document" : suggestedTitle,
                thumbnailData: thumbnail,
                ocrText: text,
                processingWarning: warning
            )
        } catch {
            if let savedPath, (try? DocumentFileStore.deletePDF(forRelativePath: savedPath)) != nil {
                DocumentFileStore.unregisterDraftPDF(savedPath)
            }
            present(error)
        }
    }

    private func present(_ error: Error) {
        if error is CancellationError || Task.isCancelled { return }
        errorMessage = error.localizedDescription
    }

    private static let scanDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
