import AVFoundation
import SwiftUI

struct RecordedAudio {
    let fileName: String
    let duration: TimeInterval
}

@MainActor
final class AudioRecorder: NSObject, ObservableObject {
    enum RecorderError: LocalizedError {
        case microphoneDenied
        case recordingUnavailable
        case automaticStopFailed

        var errorDescription: String? {
            switch self {
            case .microphoneDenied:
                "Microphone access is off. Enable it in Settings to record, or continue with a manual finding."
            case .recordingUnavailable:
                "The microphone is unavailable. Check other audio apps and try again."
            case .automaticStopFailed:
                "Recording stopped unexpectedly and the audio could not be saved."
            }
        }
    }

    @Published private(set) var isRecording = false
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var audioLevel: Float = 0
    @Published var errorMessage: String?
    @Published private(set) var permissionDenied = false

    var onAutomaticFinish: ((Result<RecordedAudio, Error>) -> Void)?

    private var recorder: AVAudioRecorder?
    private var temporaryURL: URL?
    private var meterTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var isStarting = false

    override init() {
        super.init()
        observeInterruptions()
    }

    isolated deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        meterTimer?.invalidate()
    }

    func start() async {
        guard !isRecording, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        errorMessage = nil
        permissionDenied = false
        guard await requestPermission() else {
            permissionDenied = true
            errorMessage = RecorderError.microphoneDenied.localizedDescription
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .spokenAudio, options: [.allowBluetoothHFP])
            try session.setActive(true)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            guard recorder.record(forDuration: 7_200) else { throw RecorderError.recordingUnavailable }
            self.recorder = recorder
            temporaryURL = url
            duration = 0
            audioLevel = 0
            isRecording = true
            startMetering()
        } catch {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            errorMessage = error.localizedDescription
        }
    }

    func stop() throws -> RecordedAudio {
        guard let recorder, let temporaryURL else { throw RecorderError.recordingUnavailable }
        let measuredDuration = recorder.currentTime
        isRecording = false
        recorder.stop()
        stopMetering()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        self.recorder = nil
        self.temporaryURL = nil
        do {
            let stored = try LocalFileStore.persistRecording(at: temporaryURL)
            return RecordedAudio(fileName: stored.fileName, duration: stored.duration > 0 ? stored.duration : measuredDuration)
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
    }

    func cancel() {
        guard recorder != nil else { return }
        isRecording = false
        recorder?.stop()
        recorder = nil
        stopMetering()
        if let temporaryURL {
            try? FileManager.default.removeItem(at: temporaryURL)
        }
        temporaryURL = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func requestPermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    private func startMetering() {
        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let recorder = self.recorder else { return }
                recorder.updateMeters()
                self.duration = recorder.currentTime
                let power = recorder.averagePower(forChannel: 0)
                self.audioLevel = max(0, min(1, (power + 48) / 42))
            }
        }
    }

    private func stopMetering() {
        meterTimer?.invalidate()
        meterTimer = nil
        audioLevel = 0
    }

    private func observeInterruptions() {
        let center = NotificationCenter.default
        let interruption = center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: typeValue) == .began else { return }
            Task { @MainActor in self?.finishAutomatically() }
        }
        let resign = center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.finishAutomatically() }
        }
        observers = [interruption, resign]
    }

    private func finishAutomatically() {
        guard isRecording else { return }
        do {
            let audio = try stop()
            onAutomaticFinish?(.success(audio))
        } catch {
            errorMessage = RecorderError.automaticStopFailed.localizedDescription
            onAutomaticFinish?(.failure(error))
        }
    }
}

extension AudioRecorder: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            guard self.isRecording else { return }
            if flag {
                self.finishAutomatically()
            } else {
                self.cancel()
                self.errorMessage = RecorderError.automaticStopFailed.localizedDescription
                self.onAutomaticFinish?(.failure(RecorderError.automaticStopFailed))
            }
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            guard self.isRecording else { return }
            self.cancel()
            self.errorMessage = error?.localizedDescription ?? RecorderError.automaticStopFailed.localizedDescription
            self.onAutomaticFinish?(.failure(error ?? RecorderError.automaticStopFailed))
        }
    }
}
