import Foundation

enum RoadSurface: String {
    case paved
    case unpaved
}

/// A GIS label that names a paved surface stays paved, including "p" and "paved: asphalt".
/// A blank, unknown, gravel, or dirt label stays unpaved.
func roadSurface(from label: String) -> RoadSurface {
    let name = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if name == "p" || name == "paved" || name.hasPrefix("paved ") || name.hasPrefix("paved:") {
        return .paved
    }
    switch name {
    case "asphalt", "concrete", "chipnseal", "chip seal", "chipseal":
        return .paved
    default:
        return .unpaved
    }
}

struct ScreeningRange: Equatable {
    let low: Double
    let high: Double
}

/// V = sqrt(15 * R_ft * (e + f)). e and f are ratios. e = 0.02 means 2 percent.
func screeningMPH(radiusFeet: Double, superelevation: Double, friction: Double) -> Double {
    let inside = 15 * radiusFeet * (superelevation + friction)
    guard inside > 0 else { return 0 }
    return inside.squareRoot()
}

/// Design friction stays 0.15 paved and 0.10 unpaved for new, halfway, and unknown tread.
/// Those values are already a wet-pavement assumption. Reported wear only lowers them.
/// 4/32 uses 0.12 / 0.08. At the 2/32 wear bars, 0.10 / 0.07. This is not a measured friction coefficient.
func screeningFriction(surface: RoadSurface, tread: TreadChoice) -> Double {
    switch (surface, tread) {
    case (.paved, .low): return 0.12
    case (.paved, .bars): return 0.10
    case (.unpaved, .low): return 0.08
    case (.unpaved, .bars): return 0.07
    case (.paved, _): return 0.15
    case (.unpaved, _): return 0.10
    }
}

func screeningRange(radiusFeet: Double, surface: RoadSurface, tread: TreadChoice = .unsure) -> ScreeningRange {
    let friction = screeningFriction(surface: surface, tread: tread)
    return ScreeningRange(
        low: screeningMPH(radiusFeet: radiusFeet, superelevation: -0.02, friction: friction),
        high: screeningMPH(radiusFeet: radiusFeet, superelevation: 0.02, friction: friction)
    )
}

func effectiveSpeedMPH(speedMps: Double, accuracyMps: Double) -> Double {
    max(0, speedMps - accuracyMps) * 2.23694
}

/// The phone's reported speed. A prompt still uses effectiveSpeedMPH, which drops the uncertain part.
func measuredSpeedMPH(speedMps: Double) -> Double? {
    guard speedMps >= 0 else { return nil }
    return speedMps * 2.23694
}

func radiusBand(feet: Double) -> String {
    if feet < 150 { return "under-150" }
    if feet < 300 { return "150-300" }
    return "300-600"
}

/// Night is 7:00 pm through 5:59 am, local time.
func isNightHour(_ hour: Int) -> Bool {
    hour >= 19 || hour < 6
}

func approachContextKey(surface: RoadSurface, radiusFeet: Double, hour: Int) -> String {
    let when = isNightHour(hour) ? "night" : "day"
    return "\(surface.rawValue)|\(radiusBand(feet: radiusFeet))|\(when)"
}

func shouldSpeak(effectiveSpeed: Double, range: ScreeningRange) -> Bool {
    effectiveSpeed > range.low
}

/// Counts of this driver's past approaches in one context
/// (surface × radius band × day or night). The prior is two late and two
/// early, so a single pass cannot move the warning.
struct ApproachMemory {
    var latePasses: Int
    var earlyPasses: Int
}

/// Camera flags that are allowed to move a warning earlier.
/// A dry or smooth reading is not represented here, so it cannot raise a speed.
struct VisionCaution: Equatable {
    var standingWaterOrSnow: Bool
    var severeUnevenOnPaved: Bool
}

func baseLookAheadMeters(speedMps: Double) -> Double {
    min(450, max(100, speedMps * 7))
}

/// Physics sets the floor. Memory and the camera can only lengthen it, and
/// only up to 450 m. The screening range itself does not change here.
func lookAheadMeters(speedMps: Double, memory: ApproachMemory, vision: VisionCaution) -> Double {
    let base = baseLookAheadMeters(speedMps: speedMps)
    var multiplier = 1.0
    let realPasses = memory.latePasses + memory.earlyPasses
    let posteriorLate = Double(memory.latePasses + 2) / Double(realPasses + 4)
    if realPasses >= 3 && posteriorLate > 0.5 {
        multiplier = max(multiplier, 1.4)
    }
    if vision.standingWaterOrSnow || vision.severeUnevenOnPaved {
        multiplier = max(multiplier, 1.3)
    }
    return min(450, base * multiplier)
}

/// Stay quiet on a curve this driver has already taken under the range three
/// times, unless this pass is over the range now.
func suppressRepeatPrompt(passesUnderRange: Int, effectiveSpeed: Double, range: ScreeningRange) -> Bool {
    passesUnderRange >= 3 && effectiveSpeed <= range.low
}

let spokenWarning = "Curve ahead. Above screening range."
