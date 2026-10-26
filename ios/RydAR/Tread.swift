import Foundation

/// What the driver reports about the tires. The phone does not measure tread.
enum TreadChoice: String, CaseIterable, Identifiable {
    case fresh = "New"
    case half = "Halfway"
    case low = "Low"
    case bars = "At the bars"
    case unsure = "Not sure"

    var id: String { rawValue }

    var detail: String {
        switch self {
        case .fresh: return "About 10/32"
        case .half: return "About 6/32"
        case .low: return "About 4/32"
        case .bars: return "2/32 or less"
        case .unsure: return "Leave the usual range"
        }
    }

    /// Wear bars are the replacement point. 4/32 is the wet-grip caution.
    var replaceBeforeDriving: Bool { self == .bars }
    var lowersRange: Bool { self == .low || self == .bars }
}

enum TreadStore {
    static let choiceKey = "rydar.tread"
    static let metersKey = "rydar.treadMeters"
    /// Ask again after about 1,000 miles of driving this phone has recorded.
    static let reviewMeters = 1_000.0 * 1_609.344

    static var choice: TreadChoice? {
        guard let raw = UserDefaults.standard.string(forKey: choiceKey) else { return nil }
        return TreadChoice(rawValue: raw)
    }

    static func save(_ choice: TreadChoice) {
        UserDefaults.standard.set(choice.rawValue, forKey: choiceKey)
        UserDefaults.standard.set(0.0, forKey: metersKey)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: choiceKey)
        UserDefaults.standard.set(0.0, forKey: metersKey)
    }

    /// A parked phone drifts. Only a moving fix, over a short gap, counts toward the next tread check.
    static func countsTowardReview(meters: Double, speedMps: Double, elapsed: TimeInterval) -> Bool {
        guard speedMps >= DriveRules.movingSpeedMps else { return false }
        guard meters > 0, meters < 300 else { return false }
        guard elapsed > 0, elapsed < 30 else { return false }
        let fastest = speedMps * elapsed * 1.5 + 15
        return meters <= fastest
    }

    /// Distance comes from GPS fixes on this phone, not the car's odometer.
    static func addMeters(_ meters: Double) {
        guard meters > 0, meters < 300, choice != nil else { return }
        let next = UserDefaults.standard.double(forKey: metersKey) + meters
        if next >= reviewMeters {
            clear()
        } else {
            UserDefaults.standard.set(next, forKey: metersKey)
        }
    }
}
