import AVFoundation
import Foundation

protocol PromptPlaying: AnyObject {
    func speakWarning(_ line: String) throws
    func playCurveTap()
    func holdForTrip()
    /// Warms the haptic engine before the first warning.
    func prepareHaptics()
    func releaseAfterTrip()
}

extension PromptPlaying {
    func playCurveTap() {}
    func holdForTrip() {}
    func prepareHaptics() {}
    func releaseAfterTrip() {}
}

/// Playback session, voice-prompt mode. Other navigation speech is interrupted so this alert is not queued behind it.
/// The session stays active for the whole trip but only mixes with other audio. It ducks and interrupts
/// while an alert plays, then goes back to mixing so music returns to full volume.
/// Speaks the advisory line for this curve after the two vibrations. The audio session stays as configured below.
final class SpeechPrompt: NSObject, PromptPlaying, AVSpeechSynthesizerDelegate {
    static let category: AVAudioSession.Category = .playback
    static let mode: AVAudioSession.Mode = .voicePrompt
    /// While an alert plays.
    static let options: AVAudioSession.CategoryOptions = [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
    /// Between alerts: keep the session, leave other audio alone.
    static let idleOptions: AVAudioSession.CategoryOptions = [.mixWithOthers]
    /// The system rate. Premium and enhanced voices are written for it.
    static let speechRate = AVSpeechUtteranceDefaultSpeechRate

    private static let voiceQueue = DispatchQueue(label: "com.rydar.voice", qos: .userInitiated)
    private let synthesizer = AVSpeechSynthesizer()
    private let haptic = CurveHaptic()
    /// Category changes and setActive block long enough for AVAudioSession to warn on the main thread.
    private let sessionQueue = DispatchQueue(label: "rydar.audio-session", qos: .userInitiated)
    private var holding = false
    private var voice: AVSpeechSynthesisVoice?
    /// Incremented on release so an in-flight activation cannot speak after the trip ends.
    private var playbackGeneration = 0

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func holdForTrip() {
        holding = true
        let generation = playbackGeneration
        // Listing every installed voice is slow on a phone with many downloads. Do it off the main thread.
        Self.voiceQueue.async { [weak self] in
            let best = Self.resolvedVoice()
            DispatchQueue.main.async {
                guard let self, generation == self.playbackGeneration else { return }
                self.voice = best
            }
        }
        activateSession(alert: false, then: {})
    }

    func prepareHaptics() {
        haptic.prepare()
    }

    func playCurveTap() {
        haptic.play()
    }

    func releaseAfterTrip() {
        playbackGeneration += 1
        holding = false
        haptic.stop()
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
        let knownVoice = voice
        let delay = CurveHapticTiming.speechDelayForCurrentApp()
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let voice = knownVoice ?? Self.resolvedVoice()
            do {
                try self.activateSession(alert: true)
            } catch {
                Thread.sleep(forTimeInterval: 0.4)
                do {
                    try self.activateSession(alert: true)
                } catch {
                    return
                }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, generation == self.playbackGeneration else { return }
                self.voice = voice
                let utterance = AVSpeechUtterance(string: spoken)
                utterance.voice = voice
                utterance.rate = Self.speechRate
                utterance.preUtteranceDelay = delay
                utterance.postUtteranceDelay = 0
                self.synthesizer.speak(utterance)
            }
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
            language: { $0.language },
            identifier: { $0.identifier },
            novelty: { $0.voiceTraits.contains(.isNoveltyVoice) }
        ) {
            return best
        }
        return AVSpeechSynthesisVoice(language: languageCode)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
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
                // A call or another app can hold the session for a moment. Try once more.
                Thread.sleep(forTimeInterval: 0.4)
                do {
                    try self.activateSession(alert: alert)
                } catch {
                    return
                }
            }
            DispatchQueue.main.async(execute: completion)
        }
    }

    private func releaseSession() {
        sessionQueue.async {
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
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

    /// Best installed voice in the same language family. Premium and enhanced
    /// beat the compact default, novelty voices are skipped, and a known
    /// natural voice wins a tie. The rider's exact locale breaks a remaining tie.
    static func best<Voice>(
        from voices: [Voice],
        languageCode: String,
        quality: (Voice) -> AVSpeechSynthesisVoiceQuality,
        language: (Voice) -> String,
        identifier: (Voice) -> String = { _ in "" },
        novelty: (Voice) -> Bool = { _ in false }
    ) -> Voice? {
        let wanted = languageCode.replacingOccurrences(of: "_", with: "-")
        let family = wanted.split(separator: "-").first.map(String.init) ?? wanted
        func normalized(_ voice: Voice) -> String {
            language(voice).replacingOccurrences(of: "_", with: "-")
        }
        let pool = voices.filter { voice in
            let code = normalized(voice)
            let sameFamily = code.caseInsensitiveCompare(family) == .orderedSame
                || code.lowercased().hasPrefix(family.lowercased() + "-")
            return sameFamily && naturalScore(
                quality: quality(voice),
                language: code,
                wanted: wanted,
                identifier: identifier(voice),
                novelty: novelty(voice)
            ) >= 0
        }
        return pool.max { lhs, rhs in
            naturalScore(
                quality: quality(lhs),
                language: normalized(lhs),
                wanted: wanted,
                identifier: identifier(lhs),
                novelty: novelty(lhs)
            ) < naturalScore(
                quality: quality(rhs),
                language: normalized(rhs),
                wanted: wanted,
                identifier: identifier(rhs),
                novelty: novelty(rhs)
            )
        }
    }

    private static func naturalScore(
        quality: AVSpeechSynthesisVoiceQuality,
        language: String,
        wanted: String,
        identifier: String,
        novelty: Bool
    ) -> Int {
        let id = identifier.lowercased()
        if novelty || id.contains("eloquence") { return -1 }
        var score = rank(quality) * 100
        if id.contains("premium"), id.contains("ava") { score += 40 }
        else if id.contains("premium"), id.contains("zoe") { score += 30 }
        else if id.contains("premium"), id.contains("noelle") { score += 20 }
        else if id.contains("siri"), id.contains("premium") { score += 10 }
        if language.caseInsensitiveCompare(wanted) == .orderedSame { score += 1 }
        return score
    }
}
