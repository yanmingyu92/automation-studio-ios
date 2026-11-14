import Foundation
import SwiftUI
import UIKit
@preconcurrency import WhisperKit

enum SpeechModel: String, CaseIterable, Identifiable {
    case tiny
    case base
    case small

    var id: String { rawValue }
    var variant: String { rawValue }

    var title: String {
        switch self {
        case .tiny: "Tiny"
        case .base: "Base"
        case .small: "Small"
        }
    }

    var detail: String {
        switch self {
        case .tiny: "Fastest, smallest, multilingual"
        case .base: "Balanced speed and accuracy, multilingual"
        case .small: "Higher accuracy with a larger download"
        }
    }
}

enum TranscriptionLanguage: String, CaseIterable, Identifiable {
    case automatic
    case english
    case spanish
    case french
    case german

    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: "Detect automatically"
        case .english: "English"
        case .spanish: "Spanish"
        case .french: "French"
        case .german: "German"
        }
    }

    var code: String? {
        switch self {
        case .automatic: nil
        case .english: "en"
        case .spanish: "es"
        case .french: "fr"
        case .german: "de"
        }
    }
}

@MainActor
final class TranscriptionManager: ObservableObject {
    enum SetupState: Equatable {
        case notDownloaded
        case downloading(Double)
        case downloaded
        case loading
        case ready
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .downloading, .loading: true
            default: false
            }
        }
    }

    enum TranscriptionError: LocalizedError {
        case modelNotReady
        case missingAudio
        case alreadyInProgress

        var errorDescription: String? {
            switch self {
            case .modelNotReady:
                "Download and load a speech model in Settings before transcribing. You can still type this finding manually."
            case .missingAudio:
                "Record a voice note before starting transcription."
            case .alreadyInProgress:
                "Another recording is already being transcribed. Wait for it to finish or cancel it first."
            }
        }
    }

    @Published var selectedModel: SpeechModel {
        didSet {
            defaults.set(selectedModel.rawValue, forKey: Keys.selectedModel)
            // A different variant is not on disk yet; never present it as "downloaded, load it".
            if !setupState.isBusy, setupState != .ready {
                setupState = downloadedFolderForSelection() == nil ? .notDownloaded : .downloaded
            }
        }
    }
    @Published var language: TranscriptionLanguage {
        didSet { defaults.set(language.rawValue, forKey: Keys.language) }
    }
    @Published private(set) var setupState: SetupState = .notDownloaded {
        didSet { updateIdleTimer() }
    }
    @Published private(set) var isTranscribing = false {
        didSet { updateIdleTimer() }
    }
    @Published private(set) var activeFindingID: UUID?
    @Published private(set) var partialTranscript = ""
    @Published private(set) var statusMessage = ""

    private enum Keys {
        static let selectedModel = "transcription.selectedModel"
        static let language = "transcription.language"
        static let modelPath = "transcription.modelPath"
        static let modelVariant = "transcription.modelVariant"
    }

    private let defaults = UserDefaults.standard
    private var whisperKit: WhisperKit?
    private var modelFolder: URL?
    private var setupTask: Task<Void, Never>?
    private var isHoldingIdleTimer = false
    private let setupCancellation = CancellationFlag()
    private let transcriptionCancellation = CancellationFlag()
    private let downloadProgress = DownloadProgressBox()

    init() {
        selectedModel = SpeechModel(rawValue: defaults.string(forKey: Keys.selectedModel) ?? "") ?? .base
        language = TranscriptionLanguage(rawValue: defaults.string(forKey: Keys.language) ?? "") ?? .automatic
        restoreModelLocation()
    }

    func prepareModel() {
        guard !setupState.isBusy else { return }
        setupCancellation.reset()
        downloadProgress.clear()
        setupTask = Task { [weak self] in
            await self?.performModelPreparation()
        }
    }

    func cancelSetup() {
        guard setupState.isBusy else { return }
        setupCancellation.cancel()
        downloadProgress.cancel()
        setupTask?.cancel()
        statusMessage = "Cancelling model setup…"
    }

    /// True when a model folder exists on disk, including after a failed load.
    var hasDownloadedModel: Bool { modelFolder != nil }

    func removeModel() {
        // Unloading while a download, load, or transcription is running is unsafe; the UI disables removal then.
        guard !setupState.isBusy, !isTranscribing else { return }
        setupTask = Task { [weak self] in
            guard let self else { return }
            await self.whisperKit?.unloadModels()
            self.whisperKit = nil
            do {
                try LocalFileStore.removeModel(at: self.modelFolder)
                self.modelFolder = nil
                self.defaults.removeObject(forKey: Keys.modelPath)
                self.defaults.removeObject(forKey: Keys.modelVariant)
                self.setupState = .notDownloaded
                self.statusMessage = "The downloaded speech model was removed."
            } catch {
                self.setupState = .failed(error.localizedDescription)
            }
        }
    }

    /// Whisper emits upper-case bracketed annotations such as "[BLANK_AUDIO]" or "[MUSIC]" for audio without
    /// intelligible speech. They are not something the inspector said, so they are dropped; a recording that
    /// yields nothing else is reported as containing no speech.
    nonisolated static func removingNonSpeechAnnotations(from text: String) -> String {
        text.replacingOccurrences(of: #"\[[A-Z][A-Z _]*\]"#, with: "", options: .regularExpression)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func transcribe(audioFileName: String?, findingID: UUID) async throws -> String {
        guard !isTranscribing else { throw TranscriptionError.alreadyInProgress }
        guard let whisperKit, setupState == .ready else { throw TranscriptionError.modelNotReady }
        guard let audioFileName else { throw TranscriptionError.missingAudio }
        let audioURL = try LocalFileStore.audioURL(fileName: audioFileName)
        guard FileManager.default.fileExists(atPath: audioURL.path) else { throw TranscriptionError.missingAudio }

        transcriptionCancellation.reset()
        isTranscribing = true
        activeFindingID = findingID
        partialTranscript = ""
        statusMessage = "Transcribing on this device. Keep FieldReport open."
        defer {
            isTranscribing = false
            activeFindingID = nil
            statusMessage = ""
        }

        let decodingOptions = DecodingOptions(
            language: language.code,
            skipSpecialTokens: true,
            concurrentWorkerCount: 1,
            chunkingStrategy: .vad
        )
        let inputOptions = AudioInputOptions(
            audioLoadingMode: .incremental(chunkDurationSeconds: 120, maxBufferedChunks: 2)
        )
        let cancellation = transcriptionCancellation
        let callback: TranscriptionCallback = { [weak self] progress in
            guard !cancellation.isCancelled else { return false }
            let text = progress.text
            Task { @MainActor in
                guard self?.isTranscribing == true else { return }
                self?.partialTranscript = text
            }
            return !cancellation.isCancelled
        }

        do {
            let results = try await whisperKit.transcribe(
                audioPath: audioURL.path,
                audioInputOptions: inputOptions,
                decodeOptions: decodingOptions,
                callback: callback
            )
            guard !transcriptionCancellation.isCancelled else { throw CancellationError() }
            try Task.checkCancellation()
            return Self.removingNonSpeechAnnotations(from: results.map(\.text).joined(separator: "\n"))
        } catch {
            if transcriptionCancellation.isCancelled || error is CancellationError {
                throw CancellationError()
            }
            throw error
        }
    }

    func cancelTranscription() {
        transcriptionCancellation.cancel()
        statusMessage = "Cancelling transcription…"
    }

    private func performModelPreparation() async {
        do {
            let folder: URL
            if let existing = downloadedFolderForSelection() {
                folder = existing
            } else {
                setupState = .downloading(0)
                statusMessage = "Downloading the \(selectedModel.title) model. Recordings stay on your device."
                folder = try await WhisperKit.download(
                    variant: selectedModel.variant,
                    downloadBase: LocalFileStore.modelDirectory(),
                    useBackgroundSession: false,
                    progressCallback: { [weak self, downloadProgress] progress in
                        downloadProgress.set(progress)
                        let fraction = progress.fractionCompleted
                        Task { @MainActor in
                            guard self?.setupCancellation.isCancelled == false else { return }
                            self?.setupState = .downloading(fraction)
                        }
                    }
                )
                try Task.checkCancellation()
                if let previous = modelFolder, previous.standardizedFileURL != folder.standardizedFileURL {
                    // Only one variant is tracked; do not leave the replaced one orphaned on disk.
                    try? LocalFileStore.removeModel(at: previous)
                }
                recordModelLocation(folder)
            }

            guard !setupCancellation.isCancelled else {
                setupState = .downloaded
                statusMessage = "Model downloaded. Load it when you are ready."
                return
            }
            setupState = .loading
            statusMessage = "Loading and preparing the model for this device…"
            let config = WhisperKitConfig(
                downloadBase: try LocalFileStore.modelDirectory(),
                modelFolder: folder.path,
                verbose: false,
                prewarm: true,
                load: true,
                download: false
            )
            let pipeline = try await WhisperKit(config)
            guard !setupCancellation.isCancelled else {
                await pipeline.unloadModels()
                setupState = .downloaded
                statusMessage = "Model setup was cancelled."
                return
            }
            whisperKit = pipeline
            recordModelLocation(folder)
            setupState = .ready
            statusMessage = "Speech model ready. Transcription now works offline."
        } catch {
            if setupCancellation.isCancelled || error is CancellationError {
                setupState = downloadedFolderForSelection() == nil ? .notDownloaded : .downloaded
                statusMessage = "Model setup was cancelled."
            } else {
                setupState = .failed(error.localizedDescription)
                statusMessage = "Model setup failed. Check your connection and available storage, then try again."
            }
        }
    }

    private func recordModelLocation(_ folder: URL) {
        modelFolder = folder
        // Persist relative to the model directory: the container path changes across installs and updates.
        defaults.set(LocalFileStore.relativeModelPath(for: folder) ?? folder.path, forKey: Keys.modelPath)
        defaults.set(selectedModel.rawValue, forKey: Keys.modelVariant)
    }

    private func updateIdleTimer() {
        // Auto-lock suspends the app, which stalls or fails a download, model load, or transcription.
        let shouldHold = setupState.isBusy || isTranscribing
        guard shouldHold != isHoldingIdleTimer else { return }
        isHoldingIdleTimer = shouldHold
        UIApplication.shared.isIdleTimerDisabled = shouldHold
    }

    private func restoreModelLocation() {
        guard let path = defaults.string(forKey: Keys.modelPath),
              let folder = LocalFileStore.modelURL(storedPath: path) else { return }
        modelFolder = folder
        if let relative = LocalFileStore.relativeModelPath(for: folder), relative != path {
            defaults.set(relative, forKey: Keys.modelPath)
        }
        if let variant = defaults.string(forKey: Keys.modelVariant), let model = SpeechModel(rawValue: variant) {
            selectedModel = model
        }
        setupState = .downloaded
    }

    private func downloadedFolderForSelection() -> URL? {
        guard let modelFolder,
              defaults.string(forKey: Keys.modelVariant) == selectedModel.rawValue,
              FileManager.default.fileExists(atPath: modelFolder.path) else { return nil }
        return modelFolder
    }
}

private final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    func reset() {
        lock.lock()
        cancelled = false
        lock.unlock()
    }
}

private final class DownloadProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var progress: Progress?

    func set(_ progress: Progress) {
        lock.lock()
        self.progress = progress
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        progress?.cancel()
        lock.unlock()
    }

    func clear() {
        lock.lock()
        progress = nil
        lock.unlock()
    }
}
