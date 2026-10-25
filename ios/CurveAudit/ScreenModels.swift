import SwiftUI

enum PromptStyle: String, CaseIterable, Identifiable {
    case chimeOnly = "Chime only"
    case short = "Short"
    case normal = "Normal"
    var id: String { rawValue }
}

enum PreviewRoad: String, CaseIterable, Identifiable {
    case oldWire = "N Old Wire Rd"
    case brightwater = "Brightwater Xing"
    case canyon = "Canyon Village Rd"
    case grove = "Grove Dr"
    var id: String { rawValue }
    var county: String { self == .grove ? "Washington" : "Benton" }
    var center: MapPoint {
        switch self {
        case .oldWire: return MapPoint(longitude: -94.117058, latitude: 36.275376)
        case .brightwater: return MapPoint(longitude: -94.034242, latitude: 36.369652)
        case .canyon: return MapPoint(longitude: -93.984527, latitude: 36.320428)
        case .grove: return MapPoint(longitude: -94.019884, latitude: 36.223624)
        }
    }
}

struct DriveScreenSnapshot {
    var nextCurve: Curve?
    var distanceMeters: Double?
    var cameraEvidence: CameraEvidence?
    /// Supplied by the vision engine; the UI never chooses a classifier threshold.
    var cameraThreshold: Double = 1
    var cameraStatus = "Off · Co-pilot mode"
    var gpsStatus = "Waiting for location"
    var isPaused = false
    /// The range the trip engine used for this match. Preview and debrief keep their own copies.
    var screeningRange: ScreeningRange?
    /// Co-pilot unless this trip opened the camera.
    var tripTitle = "Co-pilot"
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
            return "On tight unpaved roads you brake late. The next prompt in that situation comes earlier."
        }
        return "Braking was late in this context. The next prompt in that situation comes earlier."
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
}

/// UI boundary for Mac A. The engine publishes snapshots and this trip's saved rows;
/// actions forward to it. No matching, location loop, recording, speech, or upload lives here.
/// Connect all actions before presenting a production session. Default is an explicit UI demo.
@MainActor
final class TripScreenBridge: ObservableObject {
    @Published var drive = DriveScreenSnapshot()
    @Published var debrief = TripScreenDebrief()
    @Published var uploadConfigured = false
    @Published private(set) var driverMode: DriverMode?

    var onStart: ((DriverMode, PromptStyle, Bool) -> Void)?
    var onPause: ((Bool) -> Void)?
    var onFinish: (() -> Void)?
    var onUploadPreference: ((Bool) -> Void)?
    var onDeleteAllData: (() throws -> Void)?
    var isConnected: Bool { onStart != nil && onPause != nil && onFinish != nil }

    func start(mode: DriverMode, style: PromptStyle, uploadOptIn: Bool) {
        driverMode = mode
        drive = DriveScreenSnapshot()
        debrief = TripScreenDebrief()
        onStart?(mode, style, mode != .under18 && uploadOptIn)
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
        driverMode = nil
        onUploadPreference?(false)
    }
}

enum ScreenDataError: LocalizedError {
    case deleteUnavailable
    var errorDescription: String? { "The trip store has not connected its delete action yet. No data was deleted." }
}
