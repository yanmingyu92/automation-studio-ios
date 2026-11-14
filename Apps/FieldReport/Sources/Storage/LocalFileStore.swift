import AVFoundation
import Foundation
import UIKit

enum LocalFileStore {
    enum StoreError: LocalizedError {
        case invalidImage
        case missingFile
        case invalidRecording

        var errorDescription: String? {
            switch self {
            case .invalidImage: "The selected item is not a readable image."
            case .missingFile: "The file is no longer available on this device."
            case .invalidRecording: "The recording is empty or could not be read."
            }
        }
    }

    private static var fileManager: FileManager { FileManager.default }

    private static func directory(_ name: String) throws -> URL {
        let root = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("FieldReport", isDirectory: true)
        let directory = root.appendingPathComponent(name, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func audioDirectory() throws -> URL { try directory("Audio") }
    /// Speech models can be downloaded again, so they are kept out of device backups.
    static func modelDirectory() throws -> URL {
        var url = try directory("Models")
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        return url
    }

    /// Path of a downloaded model relative to the model directory. The app container path changes between
    /// installs and updates, so only this relative form is safe to persist.
    static func relativeModelPath(for url: URL) -> String? {
        guard let models = try? modelDirectory().standardizedFileURL else { return nil }
        let prefix = models.path + "/"
        let candidate = url.standardizedFileURL.path
        guard candidate.hasPrefix(prefix) else { return nil }
        return String(candidate.dropFirst(prefix.count))
    }

    /// Resolves a persisted model location. Accepts the relative form and absolute paths written by earlier builds.
    static func modelURL(storedPath: String) -> URL? {
        guard let models = try? modelDirectory() else { return nil }
        var relative = storedPath
        if storedPath.hasPrefix("/") {
            guard let range = storedPath.range(of: "/FieldReport/Models/", options: .backwards) else { return nil }
            relative = String(storedPath[range.upperBound...])
        }
        guard !relative.isEmpty, !relative.split(separator: "/").contains("..") else { return nil }
        let url = models.appendingPathComponent(relative, isDirectory: true)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    static func audioURL(fileName: String) throws -> URL {
        try audioDirectory().appendingPathComponent(fileName)
    }

    static func persistRecording(at temporaryURL: URL) throws -> (fileName: String, duration: TimeInterval) {
        let values = try temporaryURL.resourceValues(forKeys: [.fileSizeKey])
        guard (values.fileSize ?? 0) > 0 else { throw StoreError.invalidRecording }
        let audioFile = try AVAudioFile(forReading: temporaryURL)
        let duration = Double(audioFile.length) / audioFile.processingFormat.sampleRate
        let fileName = UUID().uuidString + ".m4a"
        let destination = try audioURL(fileName: fileName)
        try fileManager.moveItem(at: temporaryURL, to: destination)
        try? fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: destination.path
        )
        return (fileName, duration.isFinite && duration > 0 ? duration : 0)
    }

    static func persistImage(data: Data) throws -> (fileName: String, thumbnailFileName: String) {
        guard let source = UIImage(data: data) else { throw StoreError.invalidImage }
        let identifier = UUID().uuidString
        let fileName = identifier + ".jpg"
        let thumbnailFileName = identifier + "-thumb.jpg"
        // Downscale before normalizing orientation so a full-resolution bitmap is never rendered.
        let image = source.resized(maxDimension: 2_400).normalized()
        let thumbnail = image.resized(maxDimension: 480)
        guard let imageData = image.jpegData(compressionQuality: 0.84),
              let thumbnailData = thumbnail.jpegData(compressionQuality: 0.8) else {
            throw StoreError.invalidImage
        }
        let photos = try directory("Photos")
        let thumbnails = try directory("Thumbnails")
        try imageData.write(
            to: photos.appendingPathComponent(fileName),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
        do {
            try thumbnailData.write(
                to: thumbnails.appendingPathComponent(thumbnailFileName),
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
        } catch {
            try? fileManager.removeItem(at: photos.appendingPathComponent(fileName))
            throw error
        }
        return (fileName, thumbnailFileName)
    }

    static func photoURL(fileName: String, thumbnail: Bool = false) throws -> URL {
        try directory(thumbnail ? "Thumbnails" : "Photos").appendingPathComponent(fileName)
    }

    static func loadImage(fileName: String, thumbnail: Bool = false) -> UIImage? {
        guard let url = try? photoURL(fileName: fileName, thumbnail: thumbnail) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    static func deleteAudio(fileName: String?) {
        guard let fileName, let url = try? audioURL(fileName: fileName) else { return }
        try? fileManager.removeItem(at: url)
    }

    static func deletePhoto(_ photo: FindingPhoto) {
        if let url = try? photoURL(fileName: photo.fileName) {
            try? fileManager.removeItem(at: url)
        }
        if let url = try? photoURL(fileName: photo.thumbnailFileName, thumbnail: true) {
            try? fileManager.removeItem(at: url)
        }
    }

    static func deleteFiles(for finding: Finding) {
        deleteAudio(fileName: finding.audioFileName)
        finding.photos.forEach(deletePhoto)
    }

    static func deleteFiles(for project: InspectionProject) {
        project.findings.forEach(deleteFiles)
    }

    static func removeModel(at url: URL?) throws {
        guard let url else { return }
        let models = try modelDirectory().standardizedFileURL
        let candidate = url.standardizedFileURL
        guard candidate.path.hasPrefix(models.path + "/") else { return }
        if fileManager.fileExists(atPath: candidate.path) {
            try fileManager.removeItem(at: candidate)
        }
    }
}

private extension UIImage {
    func normalized() -> UIImage {
        guard imageOrientation != .up else { return self }
        // Keep the image's own scale; the default format would multiply the pixel count by the screen scale.
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    func resized(maxDimension: CGFloat) -> UIImage {
        let largestSide = max(size.width, size.height)
        guard largestSide > maxDimension, largestSide > 0 else { return self }
        let scale = maxDimension / largestSide
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
