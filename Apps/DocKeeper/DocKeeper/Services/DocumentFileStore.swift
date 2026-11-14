import Foundation
import PDFKit
import UIKit

enum DocumentFileStoreError: LocalizedError {
    case emptyScan
    case invalidImage
    case invalidPDF
    case invalidPath
    case missingPDF
    case restorationConflict

    var errorDescription: String? {
        switch self {
        case .emptyScan: "The scan did not contain any pages."
        case .invalidImage: "The selected image could not be read."
        case .invalidPDF: "The selected file is not a readable PDF."
        case .invalidPath: "The document path is invalid."
        case .missingPDF: "The local PDF is missing. Your metadata is still available."
        case .restorationConflict: "A replacement file already exists at the original PDF path."
        }
    }
}

enum DocumentFileStore {
    struct PendingPDFDeletion {
        let originalURL: URL
        let tombstoneURL: URL?
    }

    static func documentsDirectory() throws -> URL {
        let manager = FileManager.default
        let url = try manager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("DocKeeper/Documents", isDirectory: true)
        try manager.createDirectory(at: url, withIntermediateDirectories: true)
        try migrateLegacyPDFs(to: url)
        return url
    }

    private static func migrateLegacyPDFs(to destination: URL) throws {
        let manager = FileManager.default
        guard let legacy = manager.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Documents", isDirectory: true),
              manager.fileExists(atPath: legacy.path) else { return }

        let files = try manager.contentsOfDirectory(
            at: legacy,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        for source in files where source.pathExtension.lowercased() == "pdf" {
            guard try source.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            let target = destination.appendingPathComponent(source.lastPathComponent)
            guard !manager.fileExists(atPath: target.path) else { continue }
            try manager.moveItem(at: source, to: target)
        }
    }

    static func url(forRelativePath path: String) throws -> URL {
        guard !path.isEmpty, URL(fileURLWithPath: path).lastPathComponent == path else {
            throw DocumentFileStoreError.invalidPath
        }
        return try documentsDirectory().appendingPathComponent(path)
    }

    @discardableResult
    static func savePDF(_ data: Data) throws -> String {
        guard PDFDocument(data: data) != nil else {
            throw DocumentFileStoreError.invalidPDF
        }
        let name = "\(UUID().uuidString).pdf"
        let destination = try documentsDirectory().appendingPathComponent(name)
        try data.write(to: destination, options: .atomic)
        return name
    }

    static func pdfData(forRelativePath path: String) throws -> Data {
        let url = try url(forRelativePath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw DocumentFileStoreError.missingPDF
        }
        return try Data(contentsOf: url)
    }

    static func deletePDF(forRelativePath path: String) throws {
        let url = try url(forRelativePath: path)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    // Unsaved drafts exist only in memory, so a draft PDF would be orphaned if the app
    // is terminated while the editor is open. Their file names are recorded here so the
    // next launch can remove any that never became a saved document.
    private static let pendingDraftsKey = "documents.pendingDraftPDFs"

    static var registeredDraftPDFs: [String] {
        UserDefaults.standard.stringArray(forKey: pendingDraftsKey) ?? []
    }

    static func registerDraftPDF(_ path: String) {
        var paths = registeredDraftPDFs
        guard !paths.contains(path) else { return }
        paths.append(path)
        UserDefaults.standard.set(paths, forKey: pendingDraftsKey)
    }

    static func unregisterDraftPDF(_ path: String) {
        let paths = registeredDraftPDFs.filter { $0 != path }
        if paths.isEmpty {
            UserDefaults.standard.removeObject(forKey: pendingDraftsKey)
        } else {
            UserDefaults.standard.set(paths, forKey: pendingDraftsKey)
        }
    }

    static func beginPDFDeletion(forRelativePath path: String) throws -> PendingPDFDeletion {
        let originalURL = try url(forRelativePath: path)
        let manager = FileManager.default
        guard manager.fileExists(atPath: originalURL.path) else {
            return PendingPDFDeletion(originalURL: originalURL, tombstoneURL: nil)
        }
        let tombstoneURL = try documentsDirectory()
            .appendingPathComponent(".pending-delete-\(UUID().uuidString)")
        try manager.moveItem(at: originalURL, to: tombstoneURL)
        return PendingPDFDeletion(originalURL: originalURL, tombstoneURL: tombstoneURL)
    }

    static func rollbackPDFDeletion(_ pending: PendingPDFDeletion) throws {
        guard let tombstoneURL = pending.tombstoneURL,
              FileManager.default.fileExists(atPath: tombstoneURL.path) else { return }
        guard !FileManager.default.fileExists(atPath: pending.originalURL.path) else {
            throw DocumentFileStoreError.restorationConflict
        }
        try FileManager.default.moveItem(at: tombstoneURL, to: pending.originalURL)
    }

    static func finishPDFDeletion(_ pending: PendingPDFDeletion) throws {
        guard let tombstoneURL = pending.tombstoneURL,
              FileManager.default.fileExists(atPath: tombstoneURL.path) else { return }
        try FileManager.default.removeItem(at: tombstoneURL)
    }

    static func makePDF(from images: [UIImage]) throws -> Data {
        guard !images.isEmpty else { throw DocumentFileStoreError.emptyScan }
        let firstBounds = CGRect(origin: .zero, size: images[0].size)
        let renderer = UIGraphicsPDFRenderer(bounds: firstBounds)
        let data = renderer.pdfData { context in
            for image in images {
                let bounds = CGRect(origin: .zero, size: image.size)
                context.beginPage(withBounds: bounds, pageInfo: [:])
                image.draw(in: bounds)
            }
        }
        guard PDFDocument(data: data) != nil else { throw DocumentFileStoreError.invalidPDF }
        return data
    }

    static func thumbnail(forPDFData data: Data) -> Data? {
        guard let page = PDFDocument(data: data)?.page(at: 0) else { return nil }
        let image = page.thumbnail(of: CGSize(width: 360, height: 480), for: .cropBox)
        return image.jpegData(compressionQuality: 0.82)
    }
}
