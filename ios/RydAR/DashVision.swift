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

enum DashConsensusRole {
    /// Four of six, and the weakest of those votes clears the threshold.
    case symmetric
    /// Three of six to unpaved, five of six to return to paved.
    case material
}

/// Last six outputs of one head.
/// Friction and unevenness accept when four agree and the weakest vote clears the threshold.
/// Material switches to unpaved on three of six when the average unpaved probability clears
/// its threshold, and back to paved only on five of six. Unpaved accepted during a curve
/// approach stays until that curve is passed, the approach moves to a different curve,
/// or `maxHold` seconds go by.
struct DashConsensus {
    static let window = 6
    static let votesNeeded = 4
    static let unpavedVotesToSwitch = 3
    static let pavedVotesToSwitch = 5
    /// A hold that never sees its curve passed (a turn onto another road, lost GPS) ends here.
    static let maxHold: TimeInterval = 60
    var minimumConfidence: Double = DriveRules.cameraConfidence
    var role: DashConsensusRole = .symmetric
    private(set) var votes: [DashVote] = []
    private var unpavedProbabilities: [Double] = []
    private var label: Int?
    private var latchedConfidence = 0.0
    private var approachID: String?
    private var heldApproachID: String? {
        didSet { if heldApproachID == nil { heldSince = nil } }
    }
    private var heldSince: Date?
    private var materialDecision: DashVote?

    init(minimumConfidence: Double = DriveRules.cameraConfidence, role: DashConsensusRole = .symmetric) {
        self.minimumConfidence = minimumConfidence
        self.role = role
    }

    mutating func observe(_ probabilities: [Float], now: Date = Date()) -> DashVote? {
        releaseExpiredHold(now)
        guard let best = probabilities.enumerated().max(by: { $0.element < $1.element }) else { return nil }
        votes.append(DashVote(label: best.offset, confidence: Double(best.element)))
        if role == .material {
            let unpaved = probabilities.count > DashHead.materialUnpaved
                ? Double(probabilities[DashHead.materialUnpaved])
                : 0
            unpavedProbabilities.append(unpaved)
        }
        if votes.count > Self.window {
            votes.removeFirst(votes.count - Self.window)
        }
        if unpavedProbabilities.count > Self.window {
            unpavedProbabilities.removeFirst(unpavedProbabilities.count - Self.window)
        }
        if role == .material {
            materialDecision = makeMaterialDecision(now: now)
            return materialDecision
        }
        return accepted()
    }

    func accepted() -> DashVote? {
        if role == .material {
            return materialDecision
        }
        return symmetricAccepted()
    }

    /// The curve being approached. A nil id does not release a hold; a different curve does,
    /// because the hold's own curve can no longer be passed.
    mutating func noteCurveApproach(_ curveID: String?, now: Date = Date()) {
        guard role == .material else { return }
        approachID = curveID
        guard let curveID else { return }
        if let held = heldApproachID {
            // The unpaved reading belonged to the old curve; the new one has to earn its own.
            if held != curveID { heldApproachID = nil }
        } else if label == DashHead.materialUnpaved {
            hold(curveID, now)
        }
        materialDecision = makeMaterialDecision(now: now)
    }

    private mutating func hold(_ curveID: String, _ now: Date) {
        heldApproachID = curveID
        heldSince = now
    }

    private mutating func releaseExpiredHold(_ now: Date) {
        guard let heldSince, now.timeIntervalSince(heldSince) >= Self.maxHold else { return }
        heldApproachID = nil
    }

    /// Releases the unpaved hold for this curve. Returns whether a hold was released.
    @discardableResult
    mutating func noteCurvePassed(_ curveID: String) -> Bool {
        guard role == .material, heldApproachID == curveID else { return false }
        heldApproachID = nil
        materialDecision = makeMaterialDecision()
        if label == DashHead.materialUnpaved, let approachID, approachID != curveID {
            hold(approachID, Date())
            materialDecision = makeMaterialDecision()
        }
        return true
    }

    private func symmetricAccepted() -> DashVote? {
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

    private mutating func makeMaterialDecision(now: Date = Date()) -> DashVote? {
        if heldApproachID != nil {
            return DashVote(label: DashHead.materialUnpaved, confidence: latchedConfidence)
        }
        guard votes.count == Self.window, unpavedProbabilities.count == Self.window else {
            guard let label else { return nil }
            return DashVote(label: label, confidence: latchedConfidence)
        }
        let unpavedCount = votes.reduce(into: 0) { count, vote in
            if vote.label == DashHead.materialUnpaved { count += 1 }
        }
        let pavedCount = votes.reduce(into: 0) { count, vote in
            if vote.label == DashHead.materialPaved { count += 1 }
        }
        let average = unpavedProbabilities.reduce(0, +) / Double(Self.window)
        if label != DashHead.materialUnpaved {
            if unpavedCount >= Self.unpavedVotesToSwitch, average >= minimumConfidence {
                return acceptUnpaved(confidence: average, now: now)
            }
            if label == nil, pavedCount >= Self.pavedVotesToSwitch, average < minimumConfidence {
                return acceptPaved()
            }
            guard let label else { return nil }
            return DashVote(label: label, confidence: latchedConfidence)
        }
        if pavedCount >= Self.pavedVotesToSwitch, average < minimumConfidence {
            return acceptPaved()
        }
        if average >= minimumConfidence {
            latchedConfidence = average
        }
        return DashVote(label: DashHead.materialUnpaved, confidence: latchedConfidence)
    }

    private mutating func acceptUnpaved(confidence: Double, now: Date) -> DashVote {
        label = DashHead.materialUnpaved
        latchedConfidence = confidence
        if heldApproachID == nil, let approachID {
            hold(approachID, now)
        }
        return DashVote(label: DashHead.materialUnpaved, confidence: confidence)
    }

    private mutating func acceptPaved() -> DashVote {
        label = DashHead.materialPaved
        heldApproachID = nil
        var weakest: Double?
        for vote in votes where vote.label == DashHead.materialPaved {
            if let weakest, vote.confidence >= weakest { continue }
            weakest = vote.confidence
        }
        let confidence = weakest ?? 0
        latchedConfidence = confidence
        return DashVote(label: DashHead.materialPaved, confidence: confidence)
    }
}

struct DashWindows {
    var material = DashConsensus(minimumConfidence: DriveRules.materialConfidence, role: .material)
    var friction = DashConsensus()
    var uneven = DashConsensus()

    mutating func observe(material: [Float], friction: [Float], uneven: [Float]) -> (DashVote?, DashVote?, DashVote?) {
        (
            self.material.observe(material),
            self.friction.observe(friction),
            self.uneven.observe(uneven)
        )
    }

    mutating func noteCurveApproach(_ curveID: String?) {
        material.noteCurveApproach(curveID)
    }

    @discardableResult
    mutating func noteCurvePassed(_ curveID: String) -> Bool {
        material.noteCurvePassed(curveID)
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
    func noteCurveApproach(_ curveID: String?)
    func noteCurvePassed(_ curveID: String)
    var onChange: ((DashReading) -> Void)? { get set }
}

extension DashRunning {
    func noteCurveApproach(_ curveID: String?) {}
    func noteCurvePassed(_ curveID: String) {}
}
