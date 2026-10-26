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

/// Two sharp taps at the same moment as a spoken or chimed prompt. Under-18 trips never reach this.
final class CurveHaptic {
    private var engine: CHHapticEngine?
    private var pattern: CHHapticPattern?
    /// Kept alive until the second tap has played. A local player is cancelled as soon as it is released.
    private var player: CHHapticPatternPlayer?
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
        player = nil
        engine?.stop()
        engine = nil
    }

    func play() {
        let work = {
            if hapticRoute(
                appIsActive: UIApplication.shared.applicationState == .active,
                hardwareSupportsHaptics: CHHapticEngine.capabilitiesForHardware().supportsHaptics
            ) == .taptic {
                self.playTaptic()
            } else {
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
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
            relativeTime: 0.16
        )
        return try CHHapticPattern(events: [first, second], parameters: [])
    }
}
