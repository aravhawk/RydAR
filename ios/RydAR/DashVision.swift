import CoreGraphics
import Foundation

/// Parked preference. Dash is on until someone turns it off in Settings.
/// A missing key is on. Under-18 trips ignore this and keep the camera off.
enum DashPreference {
    static let key = "rydar.dashEnabled"

    static var isOn: Bool {
        get {
            guard UserDefaults.standard.object(forKey: key) != nil else { return true }
            return UserDefaults.standard.bool(forKey: key)
        }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

extension VisionCaution {
    static let quiet = VisionCaution(standingWaterOrSnow: false, severeUnevenOnPaved: false)
}

/// Output order of the bundled model: the training heads, not a second label set.
enum DashHead {
    static let materialPaved = 0
    static let materialUnpaved = 1
    static let materialCantTell = 2
    static let frictionDry = 0
    static let frictionWet = 1
    static let frictionWater = 2
    static let frictionSnowIce = 3
    static let unevenSmooth = 0
    static let unevenSlight = 1
    static let unevenSevere = 2
}

struct DashVote {
    var label: Int
    var confidence: Double
}

/// Last six outputs of one head. Four must agree, each at least at the camera threshold.
struct DashConsensus {
    static let window = 6
    static let votesNeeded = 4
    var minimumConfidence: Double = DriveRules.cameraConfidence
    private(set) var votes: [DashVote] = []

    mutating func observe(_ probabilities: [Float]) -> DashVote? {
        guard let best = probabilities.enumerated().max(by: { $0.element < $1.element }) else { return nil }
        votes.append(DashVote(label: best.offset, confidence: Double(best.element)))
        if votes.count > Self.window {
            votes.removeFirst(votes.count - Self.window)
        }
        return accepted()
    }

    func accepted() -> DashVote? {
        guard votes.count == Self.window else { return nil }
        var grouped: [Int: [Double]] = [:]
        for vote in votes {
            grouped[vote.label, default: []].append(vote.confidence)
        }
        guard let winner = grouped.max(by: { $0.value.count < $1.value.count }),
              winner.value.count >= Self.votesNeeded,
              let confidence = winner.value.min(),
              confidence >= minimumConfidence else { return nil }
        return DashVote(label: winner.key, confidence: confidence)
    }
}

struct DashWindows {
    var material = DashConsensus(minimumConfidence: DriveRules.materialConfidence)
    var friction = DashConsensus()
    var uneven = DashConsensus()

    mutating func observe(material: [Float], friction: [Float], uneven: [Float]) -> (DashVote?, DashVote?, DashVote?) {
        (
            self.material.observe(material),
            self.friction.observe(friction),
            self.uneven.observe(uneven)
        )
    }
}

enum DashCameraState: Equatable {
    case off
    case unconfirmed
    case running
}

struct DashReading {
    var camera: CameraEvidence?
    var vision: VisionCaution
    var state: DashCameraState
    var acceptedAt: Date?
}

/// About five frames a second.
struct DashClock {
    var interval: TimeInterval = 0.2
    private var last: Date?

    mutating func allow(_ now: Date) -> Bool {
        if let last, now.timeIntervalSince(last) < interval { return false }
        last = now
        return true
    }
}

/// Lower-center crop in an image whose origin is the bottom left.
enum DashCrop {
    static func road(in extent: CGRect) -> CGRect {
        let width = extent.width * 0.5
        let height = extent.height * 0.45
        return CGRect(x: extent.midX - width / 2, y: extent.minY, width: width, height: height)
    }
}

func dashReading(
    material: DashVote?,
    friction: DashVote?,
    uneven: DashVote?,
    fileSurface: RoadSurface?,
    state: DashCameraState,
    acceptedAt: Date
) -> DashReading {
    let camera = material.flatMap { vote -> CameraEvidence? in
        guard let label = cameraLabel(for: vote.label) else { return nil }
        return CameraEvidence(
            label: label,
            confidence: vote.confidence,
            age: 0,
            onMatchedRoadROI: fileSurface != nil,
            persistent: true
        )
    }
    return DashReading(
        camera: camera,
        vision: visionCaution(material: material, friction: friction, uneven: uneven, fileSurface: fileSurface),
        state: state,
        acceptedAt: camera == nil && friction == nil && uneven == nil ? nil : acceptedAt
    )
}

func visionCaution(
    material: DashVote?,
    friction: DashVote?,
    uneven: DashVote?,
    fileSurface: RoadSurface?
) -> VisionCaution {
    let water = friction?.label == DashHead.frictionWater || friction?.label == DashHead.frictionSnowIce
    let loweredToUnpaved = fileSurface == .paved && material?.label == DashHead.materialUnpaved
    let inUsePaved = fileSurface == .paved && !loweredToUnpaved
    let severe = uneven?.label == DashHead.unevenSevere && inUsePaved
    return VisionCaution(standingWaterOrSnow: water, severeUnevenOnPaved: severe)
}

func cameraLabel(for materialIndex: Int) -> CameraLabel? {
    switch materialIndex {
    case DashHead.materialPaved:
        return .paved
    case DashHead.materialUnpaved:
        return .unpaved
    case DashHead.materialCantTell:
        return .cantTell
    default:
        return nil
    }
}

protocol DashRunning: AnyObject {
    func start()
    func stop()
    func pause()
    func noteMatchedSurface(_ surface: RoadSurface?)
    var onChange: ((DashReading) -> Void)? { get set }
}
