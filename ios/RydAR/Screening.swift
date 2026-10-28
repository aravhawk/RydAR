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

/// Reported speed minus a little of its uncertainty, never more than half a meter per second.
/// Taking all of a large accuracy figure off would hide a real overspeed.
let speedUncertaintyCapMps = 0.5

func effectiveSpeedMPH(speedMps: Double, accuracyMps: Double) -> Double {
    max(0, speedMps - min(max(0, accuracyMps), speedUncertaintyCapMps)) * 2.23694
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

/// Seconds of travel to warn before a curve. Twelve seconds sits in the
/// 10–15 second lead a driver can use (about 200–300 m at 45 mph).
let warningLeadSeconds = 12.0

/// Physics floor for a warning. Distance is speed × lead time, at least 100 m
/// when the car is slow, and never past 450 m. Memory and the onset network
/// can only lengthen this.
func baseLookAheadMeters(speedMps: Double) -> Double {
    min(450, max(100, max(0, speedMps) * warningLeadSeconds))
}

/// At least three real passes, and the late share (with a two-and-two prior) above one half.
func habitExtendsLookAhead(_ memory: ApproachMemory) -> Bool {
    let realPasses = memory.latePasses + memory.earlyPasses
    guard realPasses >= 3 else { return false }
    let posteriorLate = Double(memory.latePasses + 2) / Double(realPasses + 4)
    return posteriorLate > 0.5
}

/// Where braking started, in meters from the curve. Two imaginary on-time
/// approaches keep a single odd pass from moving the next warning.
struct OnsetMemory: Equatable {
    var count: Int
    var sumMeters: Double
    static let empty = OnsetMemory(count: 0, sumMeters: 0)

    func typicalMeters(baseMeters: Double) -> Double {
        (sumMeters + 2 * baseMeters) / (Double(count) + 2)
    }
}

/// How far out the next warning should start. A specific road wins once this
/// phone has three measured approaches on it, then the situation. Before either
/// has three, eight measured braking distances let the onset network lengthen
/// the warning. Until those exist, a mostly-late habit still stretches by 1.4.
/// The result stays at or beyond the physics distance.
func placedLookAheadMeters(
    baseMeters: Double,
    context: ApproachMemory,
    curve: ApproachMemory = ApproachMemory(latePasses: 0, earlyPasses: 0),
    contextOnset: OnsetMemory = .empty,
    curveOnset: OnsetMemory = .empty,
    onsetNet: OnsetNet = .initial,
    speedMps: Double = 0,
    radiusFeet: Double = 0,
    surface: RoadSurface = .unpaved,
    night: Bool = false
) -> Double {
    if curveOnset.count >= 3 {
        return onsetLookAhead(baseMeters: baseMeters, onset: curveOnset)
    }
    if contextOnset.count >= 3 {
        return onsetLookAhead(baseMeters: baseMeters, onset: contextOnset)
    }
    if onsetNet.canPlaceWarning {
        let predicted = onsetNet.predictMeters(
            speedMps: speedMps,
            radiusFeet: radiusFeet,
            paved: surface == .paved,
            night: night
        )
        if predicted.isFinite {
            return onsetDistanceLookAhead(baseMeters: baseMeters, typicalMeters: predicted)
        }
    }
    if habitExtendsLookAhead(context) || habitExtendsLookAhead(curve) {
        return min(450, baseMeters * 1.4)
    }
    return baseMeters
}

func onsetLookAhead(baseMeters: Double, onset: OnsetMemory) -> Double {
    onsetDistanceLookAhead(baseMeters: baseMeters, typicalMeters: onset.typicalMeters(baseMeters: baseMeters))
}

func onsetDistanceLookAhead(baseMeters: Double, typicalMeters: Double) -> Double {
    let shortfall = max(0, baseMeters - typicalMeters)
    return min(450, baseMeters + shortfall)
}

/// Physics sets the floor. Past braking, including the onset network, and the
/// camera can only lengthen it, and only up to 450 m. They do not multiply.
/// The advisory speed itself does not change here.
func lookAheadMeters(
    speedMps: Double,
    memory: ApproachMemory,
    vision: VisionCaution,
    curveMemory: ApproachMemory = ApproachMemory(latePasses: 0, earlyPasses: 0),
    contextOnset: OnsetMemory = .empty,
    curveOnset: OnsetMemory = .empty,
    onsetNet: OnsetNet = .initial,
    radiusFeet: Double = 0,
    surface: RoadSurface = .unpaved,
    night: Bool = false
) -> Double {
    let base = baseLookAheadMeters(speedMps: speedMps)
    let placed = placedLookAheadMeters(
        baseMeters: base,
        context: memory,
        curve: curveMemory,
        contextOnset: contextOnset,
        curveOnset: curveOnset,
        onsetNet: onsetNet,
        speedMps: speedMps,
        radiusFeet: radiusFeet,
        surface: surface,
        night: night
    )
    let fromCamera = (vision.standingWaterOrSnow || vision.severeUnevenOnPaved)
        ? min(450, base * 1.3)
        : base
    return min(450, max(base, placed, fromCamera))
}

/// The number a prompt says to slow to. The low end of the screening range, rounded down,
/// so a driver who is told to slow to N was above N when the warning fired
/// (`shouldSpeak` compares against the unrounded low end).
func advisorySpeedMPH(_ range: ScreeningRange) -> Int {
    max(0, Int(range.low.rounded(.down)))
}

func spokenCurveWarning(advisoryMPH: Int) -> String {
    "Slow to \(advisoryMPH) mph for the curve ahead."
}

/// Shown in settings and onboarding. A real prompt replaces N with the curve's advisory speed.
let spokenWarningPattern = "Slow to N mph for the curve ahead."

struct CurveApproach: Equatable {
    var id: String
    var distanceMeters: Double
    var advisoryMPH: Int
}

/// Back-to-back bends become one warning. A bend notably sharper than the one
/// in focus stays out of the group so it can speak on its own.
enum CurveAlerts {
    static let groupGapMeters = 400.0
    static let sharperByMPH = 8

    static func stretch(focus: CurveApproach, ahead: [CurveApproach]) -> [CurveApproach] {
        let ordered = ahead
            .filter { $0.distanceMeters + 1 >= focus.distanceMeters }
            .sorted { $0.distanceMeters < $1.distanceMeters }
        guard let start = ordered.firstIndex(where: { $0.id == focus.id }) else { return [focus] }
        var chain = [ordered[start]]
        for item in ordered.dropFirst(start + 1) {
            let gap = item.distanceMeters - chain[chain.count - 1].distanceMeters
            if gap > groupGapMeters { break }
            if item.advisoryMPH + sharperByMPH <= focus.advisoryMPH { break }
            chain.append(item)
        }
        return chain
    }

    static func spokenLine(stretch: [CurveApproach]) -> String {
        let limit = stretch.map(\.advisoryMPH).min() ?? 0
        guard stretch.count >= 2, let end = stretch.last else {
            return spokenCurveWarning(advisoryMPH: limit)
        }
        let distance = stretchDistancePhrase(meters: end.distanceMeters)
        return "Curves ahead for the next \(distance), keep it under \(limit) mph."
    }

    static func displayNotice(stretch: [CurveApproach], overAdvisory: Bool) -> String {
        if overAdvisory { return spokenLine(stretch: stretch) }
        let limit = stretch.map(\.advisoryMPH).min() ?? 0
        if stretch.count >= 2 { return "Keep it under \(limit) mph" }
        return "Advisory \(limit) mph"
    }
}

func stretchDistancePhrase(meters: Double) -> String {
    let miles = max(0, meters) / 1609.344
    if miles >= 0.4 && miles < 0.65 { return "half mile" }
    if miles >= 0.18 && miles < 0.4 { return "quarter mile" }
    if miles < 0.18 {
        let feet = max(0, meters) * 3.28084
        let rounded = max(100, Int((feet / 50).rounded()) * 50)
        return "\(rounded) feet"
    }
    let tenths = (miles * 10).rounded() / 10
    if abs(tenths - 1) < 0.05 { return "mile" }
    if abs(tenths - tenths.rounded()) < 0.001 {
        return "\(Int(tenths.rounded())) miles"
    }
    return String(format: "%.1f miles", tenths)
}
