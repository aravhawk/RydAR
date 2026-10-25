import Foundation

enum RoadSurface: String {
    case paved
    case unpaved
}

struct ScreeningRange {
    let low: Double
    let high: Double
}

/// V = sqrt(15 * R_ft * (e + f)). e and f are ratios. e = 0.02 means 2 percent.
func screeningMPH(radiusFeet: Double, superelevation: Double, friction: Double) -> Double {
    let inside = 15 * radiusFeet * (superelevation + friction)
    guard inside > 0 else { return 0 }
    return inside.squareRoot()
}

func screeningRange(radiusFeet: Double, surface: RoadSurface) -> ScreeningRange {
    let friction = surface == .paved ? 0.15 : 0.10
    return ScreeningRange(
        low: screeningMPH(radiusFeet: radiusFeet, superelevation: -0.02, friction: friction),
        high: screeningMPH(radiusFeet: radiusFeet, superelevation: 0.02, friction: friction)
    )
}

func effectiveSpeedMPH(speedMps: Double, accuracyMps: Double) -> Double {
    max(0, speedMps - accuracyMps) * 2.23694
}

func shouldSpeak(effectiveSpeed: Double, range: ScreeningRange) -> Bool {
    effectiveSpeed > range.low
}

let spokenWarning = "Curve ahead. Above screening range."
