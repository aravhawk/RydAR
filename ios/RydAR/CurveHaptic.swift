import AudioToolbox
import CoreHaptics
import UIKit

enum HapticRoute: Equatable {
    /// Custom Taptic pattern. The system only plays this while RydAR is on screen.
    case taptic
    /// System vibration. This still reaches the rider when Maps is in front.
    case vibration
}

func hapticRoute(appIsActive: Bool, hardwareSupportsHaptics: Bool) -> HapticRoute {
    if appIsActive && hardwareSupportsHaptics { return .taptic }
    return .vibration
}

enum CurveHapticTiming {
    /// Gap between the two taps while RydAR is on screen.
    static let tapticGap = 0.16
    /// Speech starts after both taps.
    static let speechAfterTaps = 0.45
    /// Gap between the two system vibrations while another app is in front.
    static let vibrationGap = 0.45
    /// Speech starts after both vibrations.
    static let speechAfterVibration = 1.05

    static func speechDelay(appIsActive: Bool, hardwareSupportsHaptics: Bool) -> TimeInterval {
        switch hapticRoute(appIsActive: appIsActive, hardwareSupportsHaptics: hardwareSupportsHaptics) {
        case .taptic: return speechAfterTaps
        case .vibration: return speechAfterVibration
        }
    }

    static func speechDelayForCurrentApp() -> TimeInterval {
        let active = Thread.isMainThread && UIApplication.shared.applicationState == .active
        return speechDelay(
            appIsActive: active,
            hardwareSupportsHaptics: CHHapticEngine.capabilitiesForHardware().supportsHaptics
        )
    }
}

/// Two vibrations, then the spoken warning. Plays for every trip that speaks, including teen trips.
final class CurveHaptic {
    private var engine: CHHapticEngine?
    private var pattern: CHHapticPattern?
    /// Kept alive until the second tap has played. A local player is cancelled as soon as it is released.
    private var player: CHHapticPatternPlayer?
    private var playback = 0
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)

    func prepare() {
        heavy.prepare()
        rigid.prepare()
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let engine = try CHHapticEngine()
            engine.isAutoShutdownEnabled = false
            engine.playsHapticsOnly = true
            engine.resetHandler = { [weak self] in
                try? self?.engine?.start()
            }
            engine.stoppedHandler = { [weak self] _ in
                try? self?.engine?.start()
            }
            self.engine = engine
            pattern = try Self.curvePattern()
            try engine.start()
        } catch {
            engine = nil
            pattern = nil
        }
    }

    func stop() {
        playback += 1
        player = nil
        engine?.resetHandler = {}
        engine?.stoppedHandler = { _ in }
        engine?.stop()
        engine = nil
    }

    func play() {
        playback += 1
        let token = playback
        let work = {
            if hapticRoute(
                appIsActive: UIApplication.shared.applicationState == .active,
                hardwareSupportsHaptics: CHHapticEngine.capabilitiesForHardware().supportsHaptics
            ) == .taptic {
                self.playTaptic()
            } else {
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                DispatchQueue.main.asyncAfter(deadline: .now() + CurveHapticTiming.vibrationGap) { [weak self] in
                    guard let self, token == self.playback else { return }
                    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                }
            }
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    private func playTaptic() {
        // UIKit taps use the Taptic Engine even while the trip's playback session is active.
        heavy.impactOccurred(intensity: 1)
        heavy.prepare()
        DispatchQueue.main.asyncAfter(deadline: .now() + CurveHapticTiming.tapticGap) { [weak self] in
            self?.rigid.impactOccurred(intensity: 1)
        }
        guard let engine, let pattern else { return }
        engine.start { [weak self] error in
            guard error == nil, let self else { return }
            do {
                let player = try engine.makePlayer(with: pattern)
                self.player = player
                try player.start(atTime: CHHapticTimeImmediate)
            } catch {
                self.player = nil
            }
        }
    }

    private static func curvePattern() throws -> CHHapticPattern {
        let first = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 1),
            ],
            relativeTime: 0
        )
        let second = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6),
            ],
            relativeTime: CurveHapticTiming.tapticGap
        )
        return try CHHapticPattern(events: [first, second], parameters: [])
    }
}
