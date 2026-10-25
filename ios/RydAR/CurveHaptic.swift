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

    func prepare() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let engine = try CHHapticEngine()
            engine.isAutoShutdownEnabled = true
            engine.playsHapticsOnly = true
            engine.resetHandler = { [weak self] in
                try? self?.engine?.start()
            }
            try engine.start()
            self.engine = engine
            pattern = try Self.curvePattern()
        } catch {
            engine = nil
            pattern = nil
        }
    }

    func stop() {
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
        if engine == nil { prepare() }
        guard let engine, let pattern else {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            return
        }
        do {
            try engine.start()
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
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
