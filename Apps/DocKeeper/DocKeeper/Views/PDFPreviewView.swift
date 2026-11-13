import PDFKit
import SwiftUI

struct PDFPreviewView: View {
    let relativePath: String

    private var url: URL? {
        try? DocumentFileStore.url(forRelativePath: relativePath)
    }

    var body: some View {
        Group {
            if let url, FileManager.default.fileExists(atPath: url.path) {
                PDFKitDocumentView(url: url)
                    .accessibilityLabel("PDF document preview")
            } else {
                ContentUnavailableView(
                    "PDF Not Available",
                    systemImage: "doc.badge.exclamationmark",
                    description: Text("The metadata is safe, but the local PDF could not be found.")
                )
            }
        }
        .background(Color(.systemBackground))
    }
}

private struct PDFKitDocumentView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .systemBackground
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
    }
}
