import AVFoundation
import SwiftUI

@MainActor
final class AudioPlayer: NSObject, ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published var errorMessage: String?

    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var interruptionObserver: NSObjectProtocol?

    override init() {
        super.init()
        // The system pauses playback on calls, alarms, and backgrounding; keep the control state in step.
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: typeValue) == .began else { return }
            Task { @MainActor in
                guard let self, self.isPlaying else { return }
                self.pause()
            }
        }
    }

    isolated deinit {
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        timer?.invalidate()
    }

    func toggle(url: URL) {
        if isPlaying {
            pause()
        } else if player != nil {
            resume()
        } else {
            play(url: url)
        }
    }

    func play(url: URL) {
        do {
            // Bluetooth HFP and explicit AirPlay options are not valid for the playback category.
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()
            self.player = player
            duration = player.duration
            currentTime = 0
            guard player.play() else {
                errorMessage = "The recording could not be played."
                return
            }
            isPlaying = true
            startTimer()
        } catch {
            errorMessage = "The recording could not be played. \(error.localizedDescription)"
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        timer?.invalidate()
        timer = nil
    }

    func resume() {
        guard let player else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        isPlaying = player.play()
        if isPlaying { startTimer() }
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        timer?.invalidate()
        timer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime
            }
        }
    }
}

extension AudioPlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.currentTime = 0
            self.timer?.invalidate()
            self.timer = nil
            self.player = nil
        }
    }
}
