import CoreLocation
import CoreMotion
import Foundation
import UIKit

enum DriveRules {
    static let matchConfidenceMinimum = 0.9
    static let requiredFixes = 3
    static let matchGapSeconds: TimeInterval = 5
    static let junctionGapMeters = 30.0
    static let onCurveMeters = 25.0
    /// Past the closest approach by this much, and no longer aimed at the curve, counts as passed.
    static let passClearMeters = 25.0
    /// A locked curve that heading has lost stays on screen while the car is still this close.
    static let lockHoldMeters = 45.0
    /// Inside that hold, moving this far back out means the curve was left behind.
    static let lockLeaveMeters = 15.0
    static let lateSpeedMeters = 40.0
    static let searchRadiusMeters = 450.0
    static let movingSpeedMps = 1.0
    static let gpsAccuracyLimitMeters = 30.0
    static let gpsMaxAgeSeconds: TimeInterval = 3
    /// Material may lower a paved file at 0.7. On the held-out sequences that
    /// kept the same precision as 0.8 and caught more unpaved frames. Water,
    /// snow, and severe stay at cameraConfidence.
    static let materialConfidence = 0.7
    static let cameraConfidence = 0.8
    static let brakingGs = 0.12
    static let brakingDeceleration = 0.5
    static let gpsOnlyDeceleration = 1.2
}

enum Geo {
    static let metersPerDegreeLatitude = 111_320.0

    static func metersPerDegreeLongitude(_ latitude: Double) -> Double {
        metersPerDegreeLatitude * cos(latitude * .pi / 180)
    }

    static func degreeSpan(latitude: Double, radiusMeters: Double) -> (latitude: Double, longitude: Double) {
        let longitudeScale = max(1, metersPerDegreeLongitude(latitude))
        return (radiusMeters / metersPerDegreeLatitude, radiusMeters / longitudeScale)
    }

    static func distanceMeters(fromLat: Double, fromLon: Double, toLat: Double, toLon: Double) -> Double {
        let east = (toLon - fromLon) * metersPerDegreeLongitude(fromLat)
        let north = (toLat - fromLat) * metersPerDegreeLatitude
        return hypot(east, north)
    }

    static func distanceToCurve(latitude: Double, longitude: Double, curve: Curve) -> Double {
        sight(latitude: latitude, longitude: longitude, courseDegrees: 0, curve: curve).distanceMeters
    }

    static func sight(latitude: Double, longitude: Double, courseDegrees: Double, curve: Curve) -> CurveSight {
        let points = curve.coordinates.isEmpty
            ? [MapPoint(longitude: curve.longitude, latitude: curve.latitude)]
            : curve.coordinates
        let longitudeScale = metersPerDegreeLongitude(latitude)
        var bestDistance = Double.greatestFiniteMagnitude
        var bestEast = 0.0
        var bestNorth = 0.0
        var bestTangent = 0.0
        if points.count == 1 {
            let east = (points[0].longitude - longitude) * longitudeScale
            let north = (points[0].latitude - latitude) * metersPerDegreeLatitude
            bestDistance = hypot(east, north)
            bestEast = east
            bestNorth = north
            bestTangent = bearing(east: east, north: north)
        } else {
            for index in 0..<(points.count - 1) {
                let start = points[index]
                let end = points[index + 1]
                let startEast = (start.longitude - longitude) * longitudeScale
                let startNorth = (start.latitude - latitude) * metersPerDegreeLatitude
                let endEast = (end.longitude - longitude) * longitudeScale
                let endNorth = (end.latitude - latitude) * metersPerDegreeLatitude
                let spanEast = endEast - startEast
                let spanNorth = endNorth - startNorth
                let lengthSquared = spanEast * spanEast + spanNorth * spanNorth
                let t: Double
                if lengthSquared < 1e-6 {
                    t = 0
                } else {
                    let projection = (-startEast * spanEast - startNorth * spanNorth) / lengthSquared
                    t = min(1, max(0, projection))
                }
                let closestEast = startEast + spanEast * t
                let closestNorth = startNorth + spanNorth * t
                let distance = hypot(closestEast, closestNorth)
                if distance < bestDistance {
                    bestDistance = distance
                    bestEast = closestEast
                    bestNorth = closestNorth
                    bestTangent = bearing(east: spanEast, north: spanNorth)
                }
            }
        }
        let error: Double
        if bestDistance < DriveRules.onCurveMeters {
            let forward = headingError(courseDegrees, bestTangent)
            let backward = headingError(courseDegrees, opposite(bestTangent))
            error = min(forward, backward)
        } else {
            error = headingError(courseDegrees, bearing(east: bestEast, north: bestNorth))
        }
        return CurveSight(distanceMeters: bestDistance, headingError: error)
    }

    static func headingError(_ course: Double, _ bearing: Double) -> Double {
        var delta = abs(normalize(course) - normalize(bearing))
        if delta > 180 { delta = 360 - delta }
        return delta
    }

    static func compass(_ degrees: Double) -> String {
        let names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((normalize(degrees) + 22.5) / 45) % 8
        return names[index]
    }

    private static func opposite(_ bearing: Double) -> Double {
        let value = bearing + 180
        return value >= 360 ? value - 360 : value
    }

    private static func normalize(_ degrees: Double) -> Double {
        let wrapped = degrees.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }

    private static func bearing(east: Double, north: Double) -> Double {
        var degrees = atan2(east, north) * 180 / .pi
        if degrees < 0 { degrees += 360 }
        return degrees
    }
}

struct CurveSight {
    var distanceMeters: Double
    var headingError: Double
}

struct LocationFix: Equatable {
    var latitude: Double
    var longitude: Double
    var speedMps: Double
    var speedAccuracyMps: Double
    var courseDegrees: Double
    var horizontalAccuracyMeters: Double
    var timestamp: Date

    init(
        latitude: Double,
        longitude: Double,
        speedMps: Double,
        speedAccuracyMps: Double,
        courseDegrees: Double,
        horizontalAccuracyMeters: Double,
        timestamp: Date
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.speedMps = speedMps
        self.speedAccuracyMps = speedAccuracyMps
        self.courseDegrees = courseDegrees
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
        self.timestamp = timestamp
    }

    init(_ location: CLLocation) {
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        speedMps = location.speed
        speedAccuracyMps = location.speedAccuracy
        courseDegrees = location.course
        horizontalAccuracyMeters = location.horizontalAccuracy
        timestamp = location.timestamp
    }
}

enum DrivePrompt: Equatable {
    case speak
    case chime
}

struct DriveGate: Equatable {
    var allowsSound: Bool
    var allowsChime: Bool
    var allowsCamera: Bool
    var allowsUpload: Bool
}

struct DriveSnapshot: Equatable {
    var driverMode: DriverMode?
    var tripID: String?
    var paused = false
    var nextCurveMeters: Double?
    var surface: RoadSurface?
    var surfaceUI: SurfaceUI?
    var cameraAllowed = false
    var uploadAllowed = false
    var matchedCurveID: String?
    var lookAheadMeters: Double?
    var lastPrompt: DrivePrompt?
    var spokenLine: String?
}

struct TripUpdate: Equatable {
    var prompt: DrivePrompt?
    var spokenLine: String?
    var gate: DriveGate
    var matchedCurveID: String?
    var matchConfidence: Double
    var matchStreak: Int
    var junctionAmbiguous: Bool
    var lookAheadMeters: Double?
    var distanceMeters: Double?
    var surface: RoadSurface?
    var surfaceUI: SurfaceUI?
    var completed: [CompletedPass]
    var gpsGood = false
    var gpsStatus = "Waiting for location"
    var measuredSpeedMPH: Double? = nil
    var promptSpeedMPH: Double? = nil
    var screeningRange: ScreeningRange? = nil
    /// What the drive screen shows for the advisory, including the mph to slow to.
    var advisoryNotice: String? = nil
    /// Uses the tightest bend in a grouped warning, rather than only the focused bend.
    var advisoryWarning: Bool? = nil
}

func driveGate(mode: DriverMode?, speedMps: Double, dashEnabled: Bool, uploadOptIn: Bool) -> DriveGate {
    guard let mode else {
        return DriveGate(allowsSound: false, allowsChime: false, allowsCamera: false, allowsUpload: false)
    }
    let sound = allowsInDriveSound(mode)
    switch mode {
    case .under18:
        return DriveGate(
            allowsSound: true,
            allowsChime: false,
            allowsCamera: false,
            allowsUpload: false
        )
    case .adult:
        return DriveGate(
            allowsSound: sound,
            allowsChime: sound,
            allowsCamera: dashEnabled,
            allowsUpload: uploadOptIn
        )
    }
}

func gpsIsGood(_ fix: LocationFix, now: Date) -> Bool {
    guard fix.horizontalAccuracyMeters >= 0,
          fix.horizontalAccuracyMeters <= DriveRules.gpsAccuracyLimitMeters else { return false }
    guard fix.speedMps >= 0, fix.speedAccuracyMps >= 0 else { return false }
    guard fix.courseDegrees >= 0, fix.courseDegrees <= 360 else { return false }
    let age = now.timeIntervalSince(fix.timestamp)
    return age >= -1 && age <= DriveRules.gpsMaxAgeSeconds
}

/// A parked phone often has a coordinate and still reports speed and course as unknown.
/// That is not a missing location. A curve match needs both.
func gpsStatusText(for fix: LocationFix, now: Date) -> String {
    if gpsIsGood(fix, now: now) { return "GPS ready" }
    let positioned = fix.horizontalAccuracyMeters >= 0
        && fix.horizontalAccuracyMeters <= DriveRules.gpsAccuracyLimitMeters
    let age = now.timeIntervalSince(fix.timestamp)
    let fresh = age >= -1 && age <= DriveRules.gpsMaxAgeSeconds
    let motionUnknown = fix.speedMps < 0 || fix.speedAccuracyMps < 0
        || fix.courseDegrees < 0 || fix.courseDegrees > 360
    if positioned && fresh && motionUnknown {
        if fix.speedMps >= DriveRules.movingSpeedMps { return "Direction unknown" }
        return "Standing still"
    }
    if fresh, fix.horizontalAccuracyMeters > DriveRules.gpsAccuracyLimitMeters, fix.horizontalAccuracyMeters.isFinite {
        return "Location is too coarse"
    }
    return "Waiting for location"
}

/// What to show before a usable fix arrives. A denied or reduced-accuracy
/// choice is not still loading.
func locationBanner(authorization: CLAuthorizationStatus, accuracy: CLAccuracyAuthorization) -> String {
    switch authorization {
    case .denied, .restricted:
        return "Location is off"
    default:
        if accuracy == .reducedAccuracy { return "Precise location is off" }
        return "Waiting for location"
    }
}

func canWarn(on curve: Curve) -> Bool {
    if !curve.qualityFlags.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
    if curve.closedLoop { return false }
    if curve.radiusFeet < 50 { return false }
    if curve.roadClass.range(of: "private", options: .caseInsensitive) != nil { return false }
    if curve.roadClass.range(of: "ramp", options: .caseInsensitive) != nil { return false }
    if isRampDesign(curve.roadDesign) { return false }
    return true
}

func isRampDesign(_ design: String) -> Bool {
    let name = design.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if name.isEmpty { return false }
    let allowed = [
        "single carriageway", "dual carriageway", "frontage road",
        "sc", "dc", "dual carriage",
    ]
    return !allowed.contains(name)
}

struct TripMatcher {
    var driverMode: DriverMode?
    var promptStyle: PromptStyle = .normal
    var dashEnabled = false
    var uploadOptIn = false
    var tread: TreadChoice = .unsure

    private var streakID: String?
    private var streak = 0
    private var lastMatchAt: Date?
    private var spokenThisPass: Set<String> = []
    private var tracks: [String: ApproachTrack] = [:]
    /// The curve the drive screen is counting down. It stays put when a close-range
    /// heading wobble drops the match below the speaking threshold.
    private var lockedID: String?
    private var lowConfidenceLockFixes = 0

    mutating func begin(driverMode: DriverMode, tread: TreadChoice = .unsure) {
        self.driverMode = driverMode
        self.tread = tread
        streakID = nil
        streak = 0
        lastMatchAt = nil
        spokenThisPass = []
        tracks = [:]
        lockedID = nil
        lowConfidenceLockFixes = 0
    }

    /// Forgets the approach in progress but keeps the trip's mode and tread. A pause means the car
    /// was parked, so a curve entered before it must not complete as a pass wherever the car resumes.
    mutating func resetApproach() {
        streakID = nil
        streak = 0
        lastMatchAt = nil
        spokenThisPass = []
        tracks = [:]
        lockedID = nil
        lowConfidenceLockFixes = 0
    }

    mutating func end() {
        driverMode = nil
        streakID = nil
        streak = 0
        lastMatchAt = nil
        spokenThisPass = []
        tracks = [:]
        lockedID = nil
        lowConfidenceLockFixes = 0
    }

    mutating func ingest(
        fix: LocationFix,
        nearby: [Curve],
        memoryForContext: (String) -> ApproachMemory = { _ in ApproachMemory(latePasses: 0, earlyPasses: 0) },
        passesUnderRange: (String) -> Int = { _ in 0 },
        curveMemory: (String) -> ApproachMemory = { _ in ApproachMemory(latePasses: 0, earlyPasses: 0) },
        contextOnset: (String) -> OnsetMemory = { _ in .empty },
        curveOnset: (String) -> OnsetMemory = { _ in .empty },
        onsetNet: () -> OnsetNet = { OnsetNet.initial },
        vision: VisionCaution = VisionCaution(standingWaterOrSnow: false, severeUnevenOnPaved: false),
        camera: CameraEvidence? = nil,
        braking: Bool = false,
        now: Date? = nil
    ) -> TripUpdate {
        let moment = now ?? fix.timestamp
        let gate = driveGate(
            mode: driverMode,
            speedMps: fix.speedMps,
            dashEnabled: dashEnabled,
            uploadOptIn: uploadOptIn
        )
        guard gpsIsGood(fix, now: moment) else {
            if let lastMatchAt, moment.timeIntervalSince(lastMatchAt) > DriveRules.matchGapSeconds {
                streak = 0
                streakID = nil
                self.lastMatchAt = nil
                lockedID = nil
                lowConfidenceLockFixes = 0
            }
            return TripUpdate(
                prompt: nil,
                spokenLine: nil,
                gate: gate,
                matchedCurveID: nil,
                matchConfidence: 0,
                matchStreak: 0,
                junctionAmbiguous: false,
                lookAheadMeters: nil,
                distanceMeters: nil,
                surface: nil,
                surfaceUI: nil,
                completed: [],
                gpsStatus: gpsStatusText(for: fix, now: moment),
                measuredSpeedMPH: measuredSpeedMPH(speedMps: fix.speedMps)
            )
        }

        let scored = score(
            fix: fix,
            nearby: nearby,
            moment: moment,
            gate: gate,
            vision: vision,
            camera: camera,
            memoryForContext: memoryForContext,
            curveMemory: curveMemory,
            contextOnset: contextOnset,
            curveOnset: curveOnset,
            onsetNet: onsetNet
        )
        let hot = scored
            .filter { $0.confidence >= DriveRules.matchConfidenceMinimum }
            .sorted { $0.distance < $1.distance }
        var ambiguous = false
        if hot.count >= 2, hot[1].distance - hot[0].distance < DriveRules.junctionGapMeters {
            ambiguous = true
        }
        if let lockedID {
            if let held = scored.first(where: { $0.curve.id == lockedID }) {
                lowConfidenceLockFixes = held.confidence < DriveRules.matchConfidenceMinimum
                    ? lowConfidenceLockFixes + 1 : 0
                let closerMatch = !ambiguous && hot.first.map {
                    $0.curve.id != lockedID
                        && $0.distance + DriveRules.junctionGapMeters < held.distance
                } == true
                let lostHeading = lowConfidenceLockFixes >= DriveRules.requiredFixes
                let canSwitch = held.distance > DriveRules.lockHoldMeters && (lostHeading || closerMatch)
                if !keepsLock(held, track: tracks[lockedID]) || canSwitch {
                    self.lockedID = nil
                    lowConfidenceLockFixes = 0
                }
            } else {
                self.lockedID = nil
                lowConfidenceLockFixes = 0
            }
        }
        if self.lockedID == nil, !ambiguous, let candidate = hot.first {
            self.lockedID = candidate.curve.id
            lowConfidenceLockFixes = 0
        }

        var completed: [CompletedPass] = []
        let seen = Set(scored.map { $0.curve.id })
        for item in scored {
            if tracks[item.curve.id] == nil && !item.ahead { continue }
            var track = tracks[item.curve.id] ?? ApproachTrack(
                curveID: item.curve.id,
                minDistance: item.distance,
                lastDistance: item.distance,
                approachSpeed: 0,
                courseDegrees: fix.courseDegrees,
                baseLookAhead: item.baseLookAhead,
                baseWhenBraking: nil,
                lookAhead: item.lookAhead,
                brakingOnset: nil,
                spoke: false,
                entered: false,
                fastInside40: false,
                surface: item.surface,
                vLo: item.range.low,
                vHi: item.range.high,
                radiusFeet: item.curve.radiusFeet,
                onsetSpeedMps: 0
            )
            track.lastDistance = item.distance
            track.baseLookAhead = item.baseLookAhead
            track.lookAhead = item.lookAhead
            track.surface = item.surface
            track.vLo = item.range.low
            track.vHi = item.range.high
            track.radiusFeet = item.curve.radiusFeet
            if item.distance < track.minDistance {
                track.minDistance = item.distance
                track.courseDegrees = fix.courseDegrees
            }
            if item.ahead && item.distance <= item.lookAhead && item.effective > track.approachSpeed {
                track.entered = true
                track.approachSpeed = item.effective
            }
            if item.distance <= DriveRules.lateSpeedMeters && shouldSpeak(effectiveSpeed: item.effective, range: item.range) {
                track.fastInside40 = true
            }
            // A brake beyond this warning window is for something else. Counting it
            // as an early curve brake blocks a later, real onset from moving the prompt.
            if braking, !ambiguous, lockedID == item.curve.id, track.brakingOnset == nil,
               item.distance <= item.lookAhead {
                track.brakingOnset = item.distance
                track.baseWhenBraking = item.baseLookAhead
                track.onsetSpeedMps = max(0, fix.speedMps)
            }
            if spokenThisPass.contains(item.curve.id) {
                track.spoke = true
            }
            let passed = track.entered && !item.ahead
                && item.distance > track.minDistance + DriveRules.passClearMeters
            if passed {
                tracks.removeValue(forKey: item.curve.id)
                spokenThisPass.remove(item.curve.id)
                completed.append(makePass(track, at: moment))
            } else {
                tracks[item.curve.id] = track
            }
        }
        for identifier in tracks.keys where !seen.contains(identifier) {
            guard let track = tracks.removeValue(forKey: identifier) else { continue }
            spokenThisPass.remove(identifier)
            if track.entered {
                completed.append(makePass(track, at: moment))
            }
        }

        if let lockedID, completed.contains(where: { $0.curveID == lockedID }) {
            self.lockedID = nil
            lowConfidenceLockFixes = 0
        }
        if self.lockedID == nil, !ambiguous {
            let done = Set(completed.map(\.curveID))
            if let next = hot.first(where: { !done.contains($0.curve.id) }) {
                self.lockedID = next.curve.id
                lowConfidenceLockFixes = 0
            }
        }
        let focus = lockedID.flatMap { id in scored.first { $0.curve.id == id } }
        noteStreak(for: focus, at: moment)

        var prompt: DrivePrompt?
        var spokenLine: String?
        var advisoryNotice: String?
        var advisoryWarning: Bool?
        if let focus {
            // A nearby bend on a different road is not part of this stretch.
            // Unknown road names remain single-curve warnings.
            let road = focus.curve.roadName.trimmingCharacters(in: .whitespacesAndNewlines)
            let approaches = scored.filter {
                $0.curve.id == focus.curve.id || (
                    !road.isEmpty
                        && $0.confidence >= DriveRules.matchConfidenceMinimum
                        && $0.curve.county == focus.curve.county
                        && $0.curve.roadName == focus.curve.roadName
                )
            }.filter(\.ahead).map {
                CurveApproach(
                    id: $0.curve.id,
                    distanceMeters: $0.distance,
                    advisoryMPH: advisorySpeedMPH($0.range)
                )
            }
            let focusApproach = CurveApproach(
                id: focus.curve.id,
                distanceMeters: focus.distance,
                advisoryMPH: advisorySpeedMPH(focus.range)
            )
            let stretch = CurveAlerts.stretch(focus: focusApproach, ahead: approaches)
            let tightestID = stretch.min { $0.advisoryMPH < $1.advisoryMPH }?.id ?? focus.curve.id
            let tightestRange = scored.first { $0.curve.id == tightestID }?.range ?? focus.range
            let over = shouldSpeak(effectiveSpeed: focus.effective, range: tightestRange)
            advisoryNotice = CurveAlerts.displayNotice(stretch: stretch, overAdvisory: over)
            advisoryWarning = over
            let quiet = suppressRepeatPrompt(
                passesUnderRange: passesUnderRange(focus.curve.id),
                effectiveSpeed: focus.effective,
                range: focus.range
            )
            let firstTime = !spokenThisPass.contains(focus.curve.id)
            let inWindow = focus.distance <= focus.lookAhead
            let confident = focus.confidence >= DriveRules.matchConfidenceMinimum
            let ready = over && !quiet && firstTime && inWindow && streak >= DriveRules.requiredFixes
                && confident && !ambiguous
            // Audio-only teen trips always speak the advisory, regardless of the adult prompt preference.
            let style = driverMode == .under18 ? PromptStyle.normal : promptStyle
            if ready && gate.allowsSound && style == .chimeOnly && gate.allowsChime {
                prompt = .chime
            } else if ready && gate.allowsSound && style != .chimeOnly {
                prompt = .speak
                spokenLine = CurveAlerts.spokenLine(stretch: stretch)
            }
            if prompt != nil {
                for identifier in stretch.map(\.id) {
                    spokenThisPass.insert(identifier)
                    if var track = tracks[identifier] {
                        track.spoke = true
                        tracks[identifier] = track
                    }
                }
            }
        }

        return TripUpdate(
            prompt: prompt,
            spokenLine: spokenLine,
            gate: gate,
            matchedCurveID: focus?.curve.id,
            matchConfidence: focus?.confidence ?? 0,
            matchStreak: streak,
            junctionAmbiguous: ambiguous,
            lookAheadMeters: focus?.lookAhead,
            distanceMeters: focus?.distance,
            surface: focus?.surface,
            surfaceUI: focus?.surfaceUI,
            completed: completed,
            gpsGood: true,
            gpsStatus: "GPS ready",
            measuredSpeedMPH: measuredSpeedMPH(speedMps: fix.speedMps),
            promptSpeedMPH: focus?.effective,
            screeningRange: focus?.range,
            advisoryNotice: advisoryNotice,
            advisoryWarning: advisoryWarning
        )
    }

    /// Hold a curve that was acquired at the speaking threshold until it is passed
    /// or the car has clearly left it. A heading dip near the curve does not qualify.
    private func keepsLock(_ item: ScoredCurve, track: ApproachTrack?) -> Bool {
        guard item.ahead else {
            let close = item.distance <= DriveRules.lockHoldMeters
            let leaving = track.map { item.distance > $0.minDistance + DriveRules.lockLeaveMeters } ?? true
            return close && !leaving
        }
        return true
    }

    /// The locked curve keeps earning the speaking streak, including fixes whose
    /// heading is too noisy to speak. A curve that was already confirmed does not
    /// make the next one wait out another three fixes.
    private mutating func noteStreak(for focus: ScoredCurve?, at moment: Date) {
        if let focus {
            let gap = lastMatchAt.map { moment.timeIntervalSince($0) }
            let continuous = gap.map { $0 <= DriveRules.matchGapSeconds } ?? false
            if focus.curve.id == streakID, continuous {
                streak += 1
            } else if continuous, streak >= DriveRules.requiredFixes {
                streakID = focus.curve.id
                streak = DriveRules.requiredFixes
            } else {
                streakID = focus.curve.id
                streak = 1
            }
            lastMatchAt = moment
        } else if let lastMatchAt, moment.timeIntervalSince(lastMatchAt) > DriveRules.matchGapSeconds {
            streak = 0
            streakID = nil
            self.lastMatchAt = nil
        }
    }

    private func score(
        fix: LocationFix,
        nearby: [Curve],
        moment: Date,
        gate: DriveGate,
        vision: VisionCaution,
        camera: CameraEvidence?,
        memoryForContext: (String) -> ApproachMemory,
        curveMemory: (String) -> ApproachMemory,
        contextOnset: (String) -> OnsetMemory,
        curveOnset: (String) -> OnsetMemory,
        onsetNet: () -> OnsetNet
    ) -> [ScoredCurve] {
        let hour = Calendar.current.component(.hour, from: moment)
        let night = isNightHour(hour)
        let net = onsetNet()
        let visionUsed = gate.allowsCamera
            ? vision
            : VisionCaution(standingWaterOrSnow: false, severeUnevenOnPaved: false)
        let cameraUsed = gate.allowsCamera ? camera : nil
        let speed = max(0, fix.speedMps)
        var contextMemories: [String: ApproachMemory] = [:]
        var contextOnsets: [String: OnsetMemory] = [:]
        return nearby.compactMap { curve in
            guard canWarn(on: curve) else { return nil }
            let geometry = Geo.sight(
                latitude: fix.latitude,
                longitude: fix.longitude,
                courseDegrees: fix.courseDegrees,
                curve: curve
            )
            let ahead = geometry.headingError <= 90
            let confidence = ahead ? max(0, cos(geometry.headingError * .pi / 180)) : 0
            let fused = fuseSurface(fileLabel: curve.surface, camera: cameraUsed, threshold: DriveRules.materialConfidence)
            let range = screeningRange(radiusFeet: curve.radiusFeet, surface: fused.0, tread: tread)
            let effective = effectiveSpeedMPH(speedMps: speed, accuracyMps: max(0, fix.speedAccuracyMps))
            let key = approachContextKey(surface: fused.0, radiusFeet: curve.radiusFeet, hour: hour)
            let memory = contextMemories[key] ?? memoryForContext(key)
            contextMemories[key] = memory
            let contextOnsetMemory = contextOnsets[key] ?? contextOnset(key)
            contextOnsets[key] = contextOnsetMemory
            let base = baseLookAheadMeters(speedMps: speed)
            let extended = lookAheadMeters(
                speedMps: speed,
                memory: memory,
                vision: visionUsed,
                curveMemory: curveMemory(curve.id),
                contextOnset: contextOnsetMemory,
                curveOnset: curveOnset(curve.id),
                onsetNet: net,
                radiusFeet: curve.radiusFeet,
                surface: fused.0,
                night: night
            )
            return ScoredCurve(
                curve: curve,
                distance: geometry.distanceMeters,
                confidence: confidence,
                ahead: ahead,
                lookAhead: max(extended, base),
                baseLookAhead: base,
                surface: fused.0,
                surfaceUI: fused.1,
                range: range,
                effective: effective
            )
        }
    }

    private func makePass(_ track: ApproachTrack, at moment: Date) -> CompletedPass {
        let hour = Calendar.current.component(.hour, from: moment)
        let late = passWasLate(
            brakingOnsetDistanceMeters: track.brakingOnset,
            baseLookAheadMeters: track.baseWhenBraking ?? track.baseLookAhead,
            fastAboveRangeInsideFortyMeters: track.fastInside40
        )
        return CompletedPass(
            curveID: track.curveID,
            direction: Geo.compass(track.courseDegrees),
            effectiveSpeedMPH: track.approachSpeed,
            vLoMPH: track.vLo,
            vHiMPH: track.vHi,
            spoke: track.spoke,
            hourBucket: hour,
            late: late,
            surfaceUsed: track.surface,
            radiusBand: radiusBand(feet: track.radiusFeet),
            lookAheadMeters: track.lookAhead,
            contextKey: approachContextKey(surface: track.surface, radiusFeet: track.radiusFeet, hour: hour),
            brakingDistanceMeters: track.brakingOnset,
            onsetSpeedMps: track.brakingOnset == nil ? nil : track.onsetSpeedMps,
            onsetRadiusFeet: track.radiusFeet
        )
    }
}

private struct ScoredCurve {
    var curve: Curve
    var distance: Double
    var confidence: Double
    var ahead: Bool
    var lookAhead: Double
    var baseLookAhead: Double
    var surface: RoadSurface
    var surfaceUI: SurfaceUI
    var range: ScreeningRange
    var effective: Double
}

private struct ApproachTrack {
    var curveID: String
    var minDistance: Double
    var lastDistance: Double
    var approachSpeed: Double
    var courseDegrees: Double
    var baseLookAhead: Double
    var baseWhenBraking: Double?
    var lookAhead: Double
    var brakingOnset: Double?
    var spoke: Bool
    var entered: Bool
    var fastInside40: Bool
    var surface: RoadSurface
    var vLo: Double
    var vHi: Double
    var radiusFeet: Double
    var onsetSpeedMps: Double
}

final class TripEngine: NSObject, CLLocationManagerDelegate {
    let locationManager = CLLocationManager()
    let motionManager = CMMotionManager()

    var promptStyle: PromptStyle = .normal
    var dashEnabled = false
    var uploadOptIn = false
    var tread: TreadChoice = .unsure
    /// Screen hook. The engine still matches, speaks, and logs. The screen does not.
    var onHandled: ((TripUpdate, Curve?) -> Void)?
    /// Fires when location permission changes during a trip, including a denial.
    var onLocationAuthorization: (() -> Void)?
    private(set) var snapshot = DriveSnapshot()

    private let store: any CurveStore
    private let passLog: PassLog
    private let speech: any PromptPlaying
    private var matcher = TripMatcher()
    private var tripID: String?
    private var paused = false
    private var sensorsWanted = true
    private var latestVision = VisionCaution(standingWaterOrSnow: false, severeUnevenOnPaved: false)
    private var latestCamera: CameraEvidence?
    private var cameraAcceptedAt: Date?
    /// Written on the motion queue at 100 Hz, read on the main thread once per fix.
    private var horizontalGs: [Double] = []
    private let motionLock = NSLock()
    /// Curves near the last database lookup, so a fix does not query and parse JSON every second.
    private var nearbyCache: (latitude: Double, longitude: Double, curves: [Curve])?
    private static let nearbyCacheMarginMeters = 100.0
    private var lastSpeedSample: (speed: Double, accuracy: Double, time: Date)?
    private var previousLocation: CLLocation?
    /// True only after a driver trip has taken the audio session.
    private var speechHeld = false
    private let precisePurposeKey = "PreciseCurve"
    private let askedAlwaysKey = "rydar.askedAlwaysLocation"
    private let askedPreciseKey = "rydar.askedPreciseLocation"
    private let motionQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.rydar.motion"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    init(store: any CurveStore, passLog: PassLog, speech: any PromptPlaying) {
        self.store = store
        self.passLog = passLog
        self.speech = speech
        super.init()
        locationManager.delegate = self
        configurePreciseLocation()
        motionManager.deviceMotionUpdateInterval = 0.01
    }

    /// Opens the bundled curve file. Does not query every row, load Core ML, or start sensors.
    static func bundled() throws -> TripEngine {
        TripEngine(
            store: try SQLiteCurveStore.openBundled(),
            passLog: try PassLog(databaseURL: BundledCurves.prepareUserData()),
            speech: SpeechPrompt()
        )
    }

    func beginTrip(driverMode: DriverMode, at date: Date = Date(), startSensors: Bool = true) throws {
        if speechHeld {
            speech.releaseAfterTrip()
            speechHeld = false
        }
        let reported = TreadStore.choice ?? .unsure
        tread = reported
        matcher.begin(driverMode: driverMode, tread: reported)
        tripID = try passLog.startTrip(mode: driverMode, at: date, notes: nil)
        setScreenAwake(driverMode != .under18)
        previousLocation = nil
        nearbyCache = nil
        resetMotionTracking()
        paused = false
        latestVision = VisionCaution(standingWaterOrSnow: false, severeUnevenOnPaved: false)
        latestCamera = nil
        cameraAcceptedAt = nil
        snapshot.driverMode = driverMode
        snapshot.tripID = tripID
        snapshot.paused = false
        sensorsWanted = startSensors
        guard startSensors else { return }
        if allowsInDriveSound(driverMode) {
            speech.holdForTrip()
            speechHeld = true
        }
        startSensorsIfNeeded()
        if driverMode == .adult {
            DriveLiveActivity.begin(speaks: true)
        } else {
            DriveLiveActivity.end()
        }
    }

    func endTrip() {
        setScreenAwake(false)
        let releaseSpeech = speechHeld
        speechHeld = false
        paused = false
        if releaseSpeech {
            speech.releaseAfterTrip()
        }
        DriveLiveActivity.end()
        locationManager.stopUpdatingLocation()
        if motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
        }
        resetMotionTracking()
        matcher.end()
        tripID = nil
        latestVision = VisionCaution(standingWaterOrSnow: false, severeUnevenOnPaved: false)
        latestCamera = nil
        cameraAcceptedAt = nil
        snapshot.driverMode = nil
        snapshot.tripID = nil
        snapshot.paused = false
    }

    func pause() {
        paused = true
        matcher.resetApproach()
        nearbyCache = nil
        if speechHeld {
            speech.releaseAfterTrip()
            speechHeld = false
        }
        locationManager.stopUpdatingLocation()
        if motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
        }
        resetMotionTracking()
        snapshot.paused = true
    }

    func resume() {
        guard matcher.driverMode != nil else { return }
        paused = false
        snapshot.paused = false
        guard sensorsWanted else { return }
        if matcher.driverMode.map(allowsInDriveSound) == true {
            speech.holdForTrip()
            speechHeld = true
        }
        startSensorsIfNeeded()
    }

    func waitingStatus() -> String {
        locationBanner(
            authorization: locationManager.authorizationStatus,
            accuracy: locationManager.accuracyAuthorization
        )
    }

    func updateVision(_ caution: VisionCaution, camera: CameraEvidence?, acceptedAt: Date = Date()) {
        latestVision = caution
        latestCamera = camera
        cameraAcceptedAt = camera == nil ? nil : acceptedAt
    }

    @discardableResult
    func handle(
        fix: LocationFix,
        nearby explicit: [Curve]? = nil,
        braking: Bool = false,
        now: Date? = nil
    ) -> TripUpdate {
        let moment = now ?? Date()
        matcher.promptStyle = promptStyle
        matcher.dashEnabled = dashEnabled
        matcher.uploadOptIn = uploadOptIn
        let nearby = explicit ?? nearbyCurves(for: fix)
        let update = matcher.ingest(
            fix: fix,
            nearby: nearby,
            memoryForContext: { key in
                (try? self.passLog.memory(for: key)) ?? ApproachMemory(latePasses: 0, earlyPasses: 0)
            },
            passesUnderRange: { identifier in
                (try? self.passLog.passesUnderRange(curveID: identifier)) ?? 0
            },
            curveMemory: { identifier in
                (try? self.passLog.curveMemory(for: identifier)) ?? ApproachMemory(latePasses: 0, earlyPasses: 0)
            },
            contextOnset: { key in
                (try? self.passLog.onset(forContext: key)) ?? .empty
            },
            curveOnset: { identifier in
                (try? self.passLog.onset(forCurve: identifier)) ?? .empty
            },
            onsetNet: {
                (try? self.passLog.onsetNet()) ?? OnsetNet.initial
            },
            vision: latestVision,
            camera: cameraForIngest(at: moment),
            braking: braking,
            now: moment
        )
        if let tripID {
            for pass in update.completed {
                do {
                    try passLog.record(pass, tripID: tripID)
                } catch {
                    print("Pass log failed: \(error)")
                }
            }
        }
        if !paused {
            switch update.prompt {
            case .speak:
                if matcher.driverMode == .adult { speech.playCurveTap() }
                if let line = update.spokenLine {
                    try? speech.speakWarning(line)
                }
            case .chime:
                if matcher.driverMode == .adult { speech.playCurveTap() }
                try? speech.playChime()
            case nil:
                break
            }
        }
        publish(update)
        let matched = update.gpsGood
            ? update.matchedCurveID.flatMap { id in nearby.first { $0.id == id } }
            : nil
        onHandled?(update, matched)
        return update
    }

    /// Looks up a wider circle once, then reuses it while the phone stays within the margin.
    /// Every fix still keeps only the curves inside the search radius, as before.
    private func nearbyCurves(for fix: LocationFix) -> [Curve] {
        let margin = Self.nearbyCacheMarginMeters
        if let cache = nearbyCache,
           Geo.distanceMeters(
               fromLat: cache.latitude, fromLon: cache.longitude,
               toLat: fix.latitude, toLon: fix.longitude
           ) <= margin {
            return withinSearchRadius(cache.curves, of: fix)
        }
        let wide = store.curves(
            nearLatitude: fix.latitude,
            longitude: fix.longitude,
            radiusMeters: DriveRules.searchRadiusMeters + margin
        )
        nearbyCache = (fix.latitude, fix.longitude, wide)
        return withinSearchRadius(wide, of: fix)
    }

    private func withinSearchRadius(_ curves: [Curve], of fix: LocationFix) -> [Curve] {
        curves.filter {
            Geo.distanceToCurve(latitude: fix.latitude, longitude: fix.longitude, curve: $0)
                <= DriveRules.searchRadiusMeters
        }
    }

    private func cameraForIngest(at moment: Date) -> CameraEvidence? {
        guard let latestCamera, let cameraAcceptedAt else { return nil }
        return CameraEvidence(
            label: latestCamera.label,
            confidence: latestCamera.confidence,
            age: max(0, moment.timeIntervalSince(cameraAcceptedAt)),
            onMatchedRoadROI: latestCamera.onMatchedRoadROI,
            persistent: latestCamera.persistent
        )
    }

    /// Deletes trips, passes, and timing memory. The curve table stays. Sensors stop.
    func deletePassHistory() throws {
        try passLog.deleteAll()
        endTrip()
        uploadOptIn = false
    }

    /// One line for the parked screen. Empty until a road on this iPhone has earned an earlier prompt.
    func timingNote() -> String {
        let roads = (try? passLog.curvesWithEarlierPrompt()) ?? 0
        guard roads > 0 else { return "" }
        let noun = roads == 1 ? "road" : "roads"
        return "Prompts come earlier on \(roads) \(noun) where you brake late."
    }

    /// Reads this trip's rows before the caller clears the trip id.
    func debrief(curves: SQLiteCurveStore) throws -> TripScreenDebrief {
        guard let tripID else { return TripScreenDebrief() }
        return try LiveTripDebrief.make(tripID: tripID, log: passLog, curves: curves)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard tripID != nil, !paused, let location = locations.last else { return }
        if let previous = previousLocation,
           location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 50,
           previous.horizontalAccuracy >= 0, previous.horizontalAccuracy <= 50 {
            let elapsed = location.timestamp.timeIntervalSince(previous.timestamp)
            let moved = location.distance(from: previous)
            if TreadStore.countsTowardReview(meters: moved, speedMps: location.speed, elapsed: elapsed) {
                TreadStore.addMeters(moved)
            }
        }
        previousLocation = location
        let fix = LocationFix(location)
        let braking = detectBraking(fix)
        handle(fix: fix, braking: braking, now: Date())
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard tripID != nil, !paused else { return }
        beginPreciseBackgroundUpdates()
        onLocationAuthorization?()
    }

    deinit {
        locationManager.stopUpdatingLocation()
        motionManager.stopDeviceMotionUpdates()
        setScreenAwake(false)
    }

    /// Driver trips stay awake through pause. Audio-only teen trips allow the screen to sleep.
    private func setScreenAwake(_ awake: Bool) {
        let apply = { UIApplication.shared.isIdleTimerDisabled = awake }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    private func startSensorsIfNeeded() {
        beginPreciseBackgroundUpdates()
        startMotion()
    }

    /// Best-for-navigation accuracy, Precise Location, and location updates that continue with Maps in front.
    private func configurePreciseLocation() {
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.activityType = .automotiveNavigation
        locationManager.distanceFilter = kCLDistanceFilterNone
    }

    private func beginPreciseBackgroundUpdates() {
        configurePreciseLocation()
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse where !UserDefaults.standard.bool(forKey: askedAlwaysKey):
            UserDefaults.standard.set(true, forKey: askedAlwaysKey)
            locationManager.requestAlwaysAuthorization()
        case .denied, .restricted:
            return
        default:
            break
        }
        if locationManager.accuracyAuthorization == .reducedAccuracy,
           !UserDefaults.standard.bool(forKey: askedPreciseKey) {
            UserDefaults.standard.set(true, forKey: askedPreciseKey)
            locationManager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: precisePurposeKey)
        }
        if locationManager.authorizationStatus == .authorizedAlways
            || locationManager.authorizationStatus == .authorizedWhenInUse {
            locationManager.allowsBackgroundLocationUpdates = true
            locationManager.showsBackgroundLocationIndicator = true
        }
        locationManager.startUpdatingLocation()
    }

    private func startMotion() {
        guard motionManager.isDeviceMotionAvailable, !motionManager.isDeviceMotionActive else { return }
        motionManager.deviceMotionUpdateInterval = 0.01
        motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: motionQueue) { [weak self] motion, _ in
            guard let motion else { return }
            let horizontal = hypot(motion.userAcceleration.x, motion.userAcceleration.y)
            self?.noteHorizontalG(horizontal)
        }
    }

    private func noteHorizontalG(_ value: Double) {
        motionLock.lock()
        defer { motionLock.unlock() }
        horizontalGs.append(value)
        if horizontalGs.count > 10 {
            horizontalGs.removeFirst()
        }
    }

    private func meanHorizontalG() -> Double {
        motionLock.lock()
        defer { motionLock.unlock() }
        guard !horizontalGs.isEmpty else { return 0 }
        return horizontalGs.reduce(0, +) / Double(horizontalGs.count)
    }

    private func resetMotionTracking() {
        lastSpeedSample = nil
        motionLock.lock()
        horizontalGs.removeAll()
        motionLock.unlock()
    }

    func detectBraking(_ fix: LocationFix) -> Bool {
        defer { lastSpeedSample = (fix.speedMps, max(0, fix.speedAccuracyMps), fix.timestamp) }
        guard fix.speedMps >= 0, let previous = lastSpeedSample, previous.speed >= 0 else { return false }
        let dt = fix.timestamp.timeIntervalSince(previous.time)
        guard dt > 0.2, dt < 5 else { return false }
        let drop = previous.speed - fix.speedMps
        let deceleration = drop / dt
        let meanG = meanHorizontalG()
        if meanG >= DriveRules.brakingGs && deceleration >= DriveRules.brakingDeceleration {
            return true
        }
        let noise = previous.accuracy + max(0, fix.speedAccuracyMps)
        if !motionManager.isDeviceMotionActive && drop > noise && deceleration >= DriveRules.gpsOnlyDeceleration {
            return true
        }
        return false
    }

    private func publish(_ update: TripUpdate) {
        snapshot = DriveSnapshot(
            driverMode: matcher.driverMode,
            tripID: tripID,
            paused: paused,
            nextCurveMeters: update.distanceMeters,
            surface: update.surface,
            surfaceUI: update.surfaceUI,
            cameraAllowed: update.gate.allowsCamera,
            uploadAllowed: update.gate.allowsUpload,
            matchedCurveID: update.matchedCurveID,
            lookAheadMeters: update.lookAheadMeters,
            lastPrompt: update.prompt ?? snapshot.lastPrompt,
            spokenLine: update.spokenLine ?? snapshot.spokenLine
        )
    }
}
