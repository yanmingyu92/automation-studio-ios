import AVFoundation

/// Short synthesised tones for moves. No audio files are bundled; every tone is rendered in memory.
@MainActor
final class SoundPlayer {
    static let shared = SoundPlayer()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
    private var cache = [String: AVAudioPCMBuffer]()
    private var prepared = false
    private var arpeggio: Task<Void, Never>?

    /// C major pentatonic from C5.
    private static let scale: [Double] = [523.25, 587.33, 659.25, 783.99, 880.0, 1046.5, 1174.66, 1318.51, 1567.98]

    private var enabled: Bool {
        UserDefaults.standard.object(forKey: SettingKey.sounds) as? Bool ?? true
    }

    func mark() {
        play(frequency: 880, duration: 0.05, gain: 0.07)
    }

    func lantern(step: Int) {
        play(frequency: Self.scale[step % Self.scale.count], duration: 0.3, gain: 0.2)
    }

    func solved(notes: Int) {
        guard enabled else { return }
        arpeggio?.cancel()
        arpeggio = Task { [weak self] in
            for index in 0..<min(max(notes, 3), Self.scale.count) {
                self?.play(frequency: Self.scale[index], duration: 0.45, gain: 0.2)
                try? await Task.sleep(for: .milliseconds(80))
                if Task.isCancelled { return }
            }
        }
    }

    private func play(frequency: Double, duration: Double, gain: Float) {
        guard enabled, let format, prepare(format) else { return }
        let key = "\(frequency)-\(duration)-\(gain)"
        let buffer: AVAudioPCMBuffer
        if let cached = cache[key] {
            buffer = cached
        } else {
            guard let rendered = render(frequency: frequency, duration: duration, gain: gain, format: format) else { return }
            cache[key] = rendered
            buffer = rendered
        }
        if !engine.isRunning {
            do { try engine.start() } catch { return }
        }
        player.scheduleBuffer(buffer, at: nil, options: [])
        if !player.isPlaying { player.play() }
    }

    /// Sets up the audio graph once. Sound is optional, so failures simply leave the game silent.
    private func prepare(_ format: AVAudioFormat) -> Bool {
        if prepared { return true }
        do {
            // Ambient: mixes with the player's own music and obeys the silent switch.
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            try engine.start()
            prepared = true
            return true
        } catch {
            return false
        }
    }

    private func render(frequency: Double, duration: Double, gain: Float, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(format.sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let samples = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        let attack = 0.005
        for frame in 0..<Int(frames) {
            let time = Double(frame) / format.sampleRate
            let envelope = min(time / attack, 1) * exp(-time * 5 / duration)
            let wave = sin(2 * .pi * frequency * time) + 0.3 * sin(4 * .pi * frequency * time)
            samples[frame] = Float(wave * envelope) * gain
        }
        return buffer
    }
}
