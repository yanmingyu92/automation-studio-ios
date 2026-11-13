import Foundation
import PDFKit
import Vision

enum VisionOCRError: LocalizedError {
    case unreadablePDF
    case noPageImage
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .unreadablePDF: "Vision could not read this PDF."
        case .noPageImage: "A PDF page could not be rendered for text recognition."
        case .recognitionFailed(let message): message
        }
    }
}

actor VisionOCRService {
    func recognizeText(inPDFData data: Data) throws -> String {
        guard let document = PDFDocument(data: data), document.pageCount > 0 else {
            throw VisionOCRError.unreadablePDF
        }

        var pages: [String] = []
        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            guard let page = document.page(at: index) else { continue }
            let image = page.thumbnail(of: CGSize(width: 1800, height: 1800), for: .cropBox)
            guard let cgImage = image.cgImage else { throw VisionOCRError.noPageImage }
            let text = try recognizePage(cgImage)
            if !text.isEmpty {
                pages.append(text)
            }
        }
        return pages.joined(separator: "\n\n")
    }

    private func recognizePage(_ image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw VisionOCRError.recognitionFailed(error.localizedDescription)
        }

        let observations = request.results ?? []
        let lines = observations.compactMap { observation -> String? in
            observation.topCandidates(1).first?.string
        }
        return lines.joined(separator: "\n")
    }
}
