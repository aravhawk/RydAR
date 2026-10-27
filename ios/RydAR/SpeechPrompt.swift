import AVFoundation
import Foundation

protocol PromptPlaying: AnyObject {
    func speakWarning(_ line: String) throws
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
/// The session stays active for the whole trip but only mixes with other audio. It ducks and interrupts
/// while an alert plays, then goes back to mixing so music returns to full volume.
/// Speaks the advisory line for this curve. The audio session stays as configured below.
final class SpeechPrompt: NSObject, PromptPlaying, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    static let category: AVAudioSession.Category = .playback
    static let mode: AVAudioSession.Mode = .voicePrompt
    /// While an alert plays.
    static let options: AVAudioSession.CategoryOptions = [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
    /// Between alerts: keep the session, leave other audio alone.
    static let idleOptions: AVAudioSession.CategoryOptions = [.mixWithOthers]
    static var line: String { spokenWarning }
    /// A little under the system default. Compact voices sound less rushed here.
    static let speechRate = AVSpeechUtteranceDefaultSpeechRate * 0.95

    private let synthesizer = AVSpeechSynthesizer()
    private let haptic = CurveHaptic()
    /// Category changes and setActive block long enough for AVAudioSession to warn on the main thread.
    private let sessionQueue = DispatchQueue(label: "rydar.audio-session", qos: .userInitiated)
    private var player: AVAudioPlayer?
    private lazy var chime: Data = chimeWAV()
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
        voice = Self.resolvedVoice()
        let generation = playbackGeneration
        activateSession(alert: false) { [weak self] in
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

    func activateSession(alert: Bool = true) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(Self.category, mode: Self.mode, options: alert ? Self.options : Self.idleOptions)
        try session.setAllowHapticsAndSystemSoundsDuringRecording(true)
        try session.setActive(true)
    }

    func speakWarning(_ line: String) throws {
        let generation = playbackGeneration
        let spoken = line
        let voice = self.voice ?? Self.resolvedVoice()
        self.voice = voice
        activateSession(alert: true) { [weak self] in
            guard let self, generation == self.playbackGeneration else { return }
            self.player?.stop()
            if self.synthesizer.isSpeaking {
                self.synthesizer.stopSpeaking(at: .immediate)
            }
            let utterance = AVSpeechUtterance(string: spoken)
            utterance.voice = voice
            utterance.rate = Self.speechRate
            utterance.preUtteranceDelay = 0
            utterance.postUtteranceDelay = 0
            self.synthesizer.speak(utterance)
        }
    }

    /// Warning text is English. Prefer the user's English locale, or US English
    /// when the device uses another language.
    static func resolvedVoice(
        languageCode: String = AVSpeechSynthesisVoice.currentLanguageCode()
    ) -> AVSpeechSynthesisVoice? {
        let languageCode = SpeechVoicePicker.warningLanguage(for: languageCode)
        let voices = AVSpeechSynthesisVoice.speechVoices()
        if let best = SpeechVoicePicker.best(
            from: voices,
            languageCode: languageCode,
            quality: { $0.quality },
            language: { $0.language }
        ) {
            return best
        }
        return AVSpeechSynthesisVoice(language: languageCode)
    }

    func playChime() throws {
        let generation = playbackGeneration
        activateSession(alert: true) { [weak self] in
            guard let self, generation == self.playbackGeneration else { return }
            if self.synthesizer.isSpeaking {
                self.synthesizer.stopSpeaking(at: .immediate)
            }
            let player: AVAudioPlayer
            do {
                player = try AVAudioPlayer(data: self.chime)
            } catch {
                return
            }
            player.delegate = self
            self.player = player
            player.play()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        alertFinished()
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        alertFinished()
    }

    /// Inside a trip, drop back to mixing so other audio returns to full volume. Outside one, release.
    private func alertFinished() {
        guard holding else {
            releaseSession()
            return
        }
        let generation = playbackGeneration
        sessionQueue.async { [weak self] in
            guard let self, generation == self.playbackGeneration else { return }
            try? self.activateSession(alert: false)
        }
    }

    /// Configures the shared session off the main thread, then continues on the main thread.
    private func activateSession(alert: Bool, then completion: @escaping () -> Void) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.activateSession(alert: alert)
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

enum SpeechVoicePicker {
    static func warningLanguage(for languageCode: String) -> String {
        let normalized = languageCode.replacingOccurrences(of: "_", with: "-")
        let family = normalized.split(separator: "-").first?.lowercased()
        return family == "en" ? normalized : "en-US"
    }

    static func rank(_ quality: AVSpeechSynthesisVoiceQuality) -> Int {
        switch quality {
        case .premium: return 3
        case .enhanced: return 2
        case .default: return 1
        @unknown default: return 1
        }
    }

    /// Best installed voice for `languageCode`: exact language first, then the
    /// same language family. Within that set, premium beats enhanced beats default.
    static func best<Voice>(
        from voices: [Voice],
        languageCode: String,
        quality: (Voice) -> AVSpeechSynthesisVoiceQuality,
        language: (Voice) -> String
    ) -> Voice? {
        let wanted = languageCode.replacingOccurrences(of: "_", with: "-")
        let family = wanted.split(separator: "-").first.map(String.init) ?? wanted
        func normalized(_ voice: Voice) -> String {
            language(voice).replacingOccurrences(of: "_", with: "-")
        }
        let exact = voices.filter { normalized($0).caseInsensitiveCompare(wanted) == .orderedSame }
        let relatives = voices.filter { voice in
            let code = normalized(voice)
            return code.caseInsensitiveCompare(family) == .orderedSame
                || code.lowercased().hasPrefix(family.lowercased() + "-")
        }
        let pool = exact.isEmpty ? relatives : exact
        return pool.max { lhs, rhs in
            rank(quality(lhs)) < rank(quality(rhs))
        }
    }
}
