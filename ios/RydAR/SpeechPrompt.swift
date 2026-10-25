import AVFoundation
import Foundation

protocol PromptPlaying: AnyObject {
    func speakWarning() throws
    func playChime() throws
}

/// Playback session, voice-prompt mode, ducking other audio. The only spoken sentence is `spokenWarning`.
final class SpeechPrompt: NSObject, PromptPlaying, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    static let category: AVAudioSession.Category = .playback
    static let mode: AVAudioSession.Mode = .voicePrompt
    static let options: AVAudioSession.CategoryOptions = [.duckOthers]
    static var line: String { spokenWarning }

    private let synthesizer = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func activateSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(Self.category, mode: Self.mode, options: Self.options)
        try session.setActive(true)
    }

    func speakWarning() throws {
        try activateSession()
        player?.stop()
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: spokenWarning)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
    }

    func playChime() throws {
        try activateSession()
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let player = try AVAudioPlayer(data: chimeWAV())
        player.delegate = self
        self.player = player
        player.play()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        releaseSession()
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        releaseSession()
    }

    private func releaseSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
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
