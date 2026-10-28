import AVFoundation
import SwiftUI

struct DriveScreenSnapshot {
    var nextCurve: Curve?
    var distanceMeters: Double?
    var cameraEvidence: CameraEvidence?
    /// Supplied by the vision engine; the UI never chooses a classifier threshold.
    var cameraThreshold: Double = 1
    var cameraStatus = "Camera check is off"
    var gpsStatus = "Waiting for location"
    var measuredSpeedMPH: Double? = nil
    /// Street, place, or coordinate while the rider is stopped. Nil once the bike is moving.
    var placeTitle: String? = nil
    /// Town, street, or coordinate that is not already the headline.
    var placeDetail: String? = nil
    /// Rider coordinate for the small drive map. Nil until a fix arrives.
    var latitude: Double? = nil
    var longitude: Double? = nil
    /// Speed after the GPS uncertainty is removed. A prompt uses this, not the measured number.
    var promptSpeedMPH: Double? = nil
    var isPaused = false
    /// The range the trip engine used for this match. Preview and debrief keep their own copies.
    var screeningRange: ScreeningRange?
    /// Says whether this trip opened the camera.
    var tripTitle = "Camera off"
    /// Advisory sentence for this approach, including the mph to slow to.
    var advisoryNotice: String?
    /// Whether the engine is warning about the current curve or a grouped stretch.
    var advisoryWarning: Bool? = nil
    /// True while the phone camera is open and frames are being read. A paused trip is not live.
    var cameraRunning = false
}

struct TripCurvePass: Identifiable {
    var id: String
    var curve: Curve
    var effectiveMPH: Double
    /// Preserve the actual surface/range used on this pass, including camera lowering.
    var range: ScreeningRange
    var surfaceUsed: RoadSurface
    var brakingDistanceMeters: Double?
    var apparentTiltDegrees: Double?
    /// Direction and hour the anonymous upload contract accepts or rejects.
    var direction: String = ""
    var hourBucket: Int = 0
    var gapAboveLowEnd: Double { max(0, effectiveMPH - range.low) }
}

struct TimingContextSummary: Identifiable {
    var surface: RoadSurface
    var representativeRadiusFeet: Double
    var hour: Int
    var memory: ApproachMemory
    var id: String {
        approachContextKey(surface: surface, radiusFeet: representativeRadiusFeet, hour: hour)
    }
    var movesPromptEarlier: Bool {
        // Ask the shared policy rather than duplicate the posterior or minimum-pass rule.
        lookAheadMeters(speedMps: 10, memory: memory,
                        vision: VisionCaution(standingWaterOrSnow: false, severeUnevenOnPaved: false))
            > baseLookAheadMeters(speedMps: 10)
    }
    var message: String {
        if surface == .unpaved && radiusBand(feet: representativeRadiusFeet) == "under-150" {
            return "You tend to brake late on tight gravel. Warnings will come earlier."
        }
        return "You tend to brake late here. Warnings will come earlier."
    }

    /// What the Review screen actually prints. Radius band is not part of it,
    /// so two paved daytime bands would otherwise be two identical cards.
    var reviewAdviceID: String {
        reviewAdviceKey(message: message, surface: surface, night: isNightHour(hour))
    }
}

/// The one place the Review dedup key is built, so a card and the contexts it merges always agree.
func reviewAdviceKey(message: String, surface: RoadSurface, night: Bool) -> String {
    "\(message)|\(surface.rawValue)|\(night ? "night" : "day")"
}

/// One Review card. Contexts that would print the same sentence are combined.
struct EarlierPromptCard: Identifiable, Equatable {
    var message: String
    var surface: RoadSurface
    var night: Bool
    var curveCount: Int
    var id: String { reviewAdviceKey(message: message, surface: surface, night: night) }
    var caption: String {
        let base = "\(surface.rawValue.capitalized) road, \(night ? "night" : "day")"
        guard curveCount > 1 else { return base }
        return "\(base) · \(curveCount) curves"
    }
}

struct TripScreenDebrief {
    var tripID = UUID().uuidString
    var passes: [TripCurvePass] = []
    var contexts: [TimingContextSummary] = []
    var overRangePasses: [TripCurvePass] {
        passes.filter { shouldSpeak(effectiveSpeed: $0.effectiveMPH, range: $0.range) }
            .sorted {
                if $0.gapAboveLowEnd == $1.gapAboveLowEnd { return $0.id < $1.id }
                return $0.gapAboveLowEnd > $1.gapAboveLowEnd
            }
    }
    var lateContexts: [TimingContextSummary] { contexts.filter(\.movesPromptEarlier) }

    /// Review advice, one card per distinct sentence. A paved day curve in a
    /// tight band and another in a wide band both say "Next prompt comes earlier."
    var earlierPromptCards: [EarlierPromptCard] {
        let late = lateContexts
        guard !late.isEmpty else { return [] }
        var groups: [String: [TimingContextSummary]] = [:]
        for context in late {
            groups[context.reviewAdviceID, default: []].append(context)
        }
        var curvesByContext: [String: Set<String>] = [:]
        for pass in passes {
            let passKey = approachContextKey(
                surface: pass.surfaceUsed,
                radiusFeet: pass.curve.radiusFeet,
                hour: pass.hourBucket
            )
            curvesByContext[passKey, default: []].insert(pass.curve.id)
        }
        return groups.keys.sorted().compactMap { key in
            guard let group = groups[key], let sample = group.first else { return nil }
            let curveIDs = group.reduce(into: Set<String>()) { $0.formUnion(curvesByContext[$1.id] ?? []) }
            return EarlierPromptCard(
                message: sample.message,
                surface: sample.surface,
                night: isNightHour(sample.hour),
                curveCount: max(group.count, curveIDs.count)
            )
        }
    }
}

/// UI boundary. The engine publishes snapshots and this trip's saved rows;
/// actions forward to it. No matching, location loop, recording, speech, or upload lives here.
/// `LiveTripSession` connects every action before the first screen appears.
@MainActor
final class TripScreenBridge: ObservableObject {
    @Published var drive = DriveScreenSnapshot()
    @Published var debrief = TripScreenDebrief()
    @Published var uploadConfigured = false
    @Published var timingNote = ""
    /// The live camera for the drive screen thumbnail. Nil whenever the camera is not running.
    @Published var cameraPreview: AVCaptureSession?
    @Published private(set) var driverMode: DriverMode?

    var onStart: ((DriverMode, Bool) -> Void)?
    var onPause: ((Bool) -> Void)?
    var onFinish: (() -> Void)?
    var onUploadPreference: ((Bool) -> Void)?
    var onDeleteAllData: (() throws -> Void)?
    var isConnected: Bool { onStart != nil && onPause != nil && onFinish != nil }

    func start(mode: DriverMode, uploadOptIn: Bool) {
        driverMode = mode
        drive = DriveScreenSnapshot()
        debrief = TripScreenDebrief()
        onStart?(mode, uploadOptIn)
    }

    func setPaused(_ paused: Bool) {
        drive.isPaused = paused
        onPause?(paused)
    }

    func finish() { onFinish?() }

    func deleteAllData() throws {
        if isConnected && onDeleteAllData == nil {
            throw ScreenDataError.deleteUnavailable
        }
        try onDeleteAllData?()
        drive = DriveScreenSnapshot()
        debrief = TripScreenDebrief()
        timingNote = ""
        driverMode = nil
        onUploadPreference?(false)
    }
}

enum ScreenDataError: LocalizedError {
    case deleteUnavailable
    var errorDescription: String? { "The trip store has not connected its delete action yet. No data was deleted." }
}
