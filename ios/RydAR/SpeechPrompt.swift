import AVFoundation
import Foundation

protocol PromptPlaying: AnyObject {
    func speakWarning() throws
    func playChime() throws
    func playCurveTap()
    func holdForTrip()
    func releaseAfterTrip()
}

extension PromptPlaying {
    func playCurveTap() {}
    func holdForTrip() {}
    func releaseAfterTrip() {}
}

/// Playback session, voice-prompt mode. Other navigation speech is interrupted so this alert is not queued behind it.
/// The session stays active for the whole trip. The only spoken sentence is `spokenWarning`.
final class SpeechPrompt: NSObject, PromptPlaying, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    static let category: AVAudioSession.Category = .playback
    static let mode: AVAudioSession.Mode = .voicePrompt
    static let options: AVAudioSession.CategoryOptions = [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
    static var line: String { spokenWarning }

    private let synthesizer = AVSpeechSynthesizer()
    private let haptic = CurveHaptic()
    /// Category changes and setActive block long enough for AVAudioSession to warn on the main thread.
    private let sessionQueue = DispatchQueue(label: "rydar.audio-session", qos: .userInitiated)
    private var player: AVAudioPlayer?
    private var holding = false
    private var voice: AVSpeechSynthesisVoice?
    /// Incremented on release so an in-flight activation cannot speak or chime after the trip ends.
    private var playbackGeneration = 0

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func holdForTrip() {
        holding = true
        voice = AVSpeechSynthesisVoice(language: "en-US")
        let generation = playbackGeneration
        activateSession { [weak self] in
            guard let self, generation == self.playbackGeneration else { return }
            self.haptic.prepare()
        }
    }

    func playCurveTap() {
        haptic.play()
    }

    func releaseAfterTrip() {
        playbackGeneration += 1
        holding = false
        haptic.stop()
        player?.stop()
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        releaseSession()
    }

    func activateSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(Self.category, mode: Self.mode, options: Self.options)
        try session.setAllowHapticsAndSystemSoundsDuringRecording(true)
        try session.setActive(true)
    }

    func speakWarning() throws {
        let generation = playbackGeneration
        activateSession { [weak self] in
            guard let self, generation == self.playbackGeneration else { return }
            self.player?.stop()
            if self.synthesizer.isSpeaking {
                self.synthesizer.stopSpeaking(at: .immediate)
            }
            let utterance = AVSpeechUtterance(string: spokenWarning)
            utterance.voice = self.voice ?? AVSpeechSynthesisVoice(language: "en-US")
            utterance.preUtteranceDelay = 0
            utterance.postUtteranceDelay = 0
            self.synthesizer.speak(utterance)
        }
    }

    func playChime() throws {
        let generation = playbackGeneration
        activateSession { [weak self] in
            guard let self, generation == self.playbackGeneration else { return }
            if self.synthesizer.isSpeaking {
                self.synthesizer.stopSpeaking(at: .immediate)
            }
            let player: AVAudioPlayer
            do {
                player = try AVAudioPlayer(data: self.chimeWAV())
            } catch {
                return
            }
            player.delegate = self
            self.player = player
            player.play()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        if !holding { releaseSession() }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if !holding { releaseSession() }
    }

    /// Configures the shared session off the main thread, then continues on the main thread.
    private func activateSession(then completion: @escaping () -> Void) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.activateSession()
            } catch {
                return
            }
            DispatchQueue.main.async(execute: completion)
        }
    }

    private func releaseSession() {
        sessionQueue.async {
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
    }

    private func chimeWAV() -> Data {
        let sampleRate = 22_050
        let frames = 3_528
        var pcm = Data(capacity: frames * 2)
        for index in 0..<frames {
            let time = Double(index) / Double(sampleRate)
            let envelope = sin(.pi * Double(index) / Double(frames))
            let value = sin(2 * .pi * 880 * time) * envelope * 0.3
            var sample = Int16(max(-1, min(1, value)) * Double(Int16.max)).littleEndian
            pcm.append(Data(bytes: &sample, count: MemoryLayout<Int16>.size))
        }
        var data = Data()
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + pcm.count), to: &data)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append(UInt32(16), to: &data)
        append(UInt16(1), to: &data)
        append(UInt16(1), to: &data)
        append(UInt32(sampleRate), to: &data)
        append(UInt32(sampleRate * 2), to: &data)
        append(UInt16(2), to: &data)
        append(UInt16(16), to: &data)
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(pcm.count), to: &data)
        data.append(pcm)
        return data
    }

    private func append(_ value: UInt32, to data: inout Data) {
        var little = value.littleEndian
        data.append(Data(bytes: &little, count: 4))
    }

    private func append(_ value: UInt16, to data: inout Data) {
        var little = value.littleEndian
        data.append(Data(bytes: &little, count: 2))
    }
}
