import CoreLocation
import CoreMotion
import Foundation

enum DriveRules {
    static let matchConfidenceMinimum = 0.9
    static let requiredFixes = 3
    static let matchGapSeconds: TimeInterval = 5
    static let cooldownSeconds: TimeInterval = 10
    static let junctionGapMeters = 30.0
    static let onCurveMeters = 25.0
    static let lateSpeedMeters = 40.0
    static let searchRadiusMeters = 450.0
    static let movingSpeedMps = 1.0
    static let gpsAccuracyLimitMeters = 30.0
    static let gpsMaxAgeSeconds: TimeInterval = 3
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
    var screeningRange: ScreeningRange? = nil
}

func driveGate(mode: DriverMode?, speedMps: Double, dashEnabled: Bool, uploadOptIn: Bool) -> DriveGate {
    guard let mode else {
        return DriveGate(allowsSound: false, allowsChime: false, allowsCamera: false, allowsUpload: false)
    }
    let moving = speedMps > DriveRules.movingSpeedMps
    let sound = allowsInDriveSound(mode)
    switch mode {
    case .under18:
        return DriveGate(
            allowsSound: false,
            allowsChime: false,
            allowsCamera: false,
            allowsUpload: uploadOptIn && !moving
        )
    case .adult, .passenger:
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

func canWarn(on curve: Curve) -> Bool {
    if !curve.qualityFlags.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
    if curve.closedLoop { return false }
    if curve.radiusFeet < 50 { return false }
    if curve.roadClass.range(of: "private", options: .caseInsensitive) != nil { return false }
    if isRampDesign(curve.roadDesign) { return false }
    return true
}

func isRampDesign(_ design: String) -> Bool {
    let name = design.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if name.isEmpty { return false }
    let allowed = ["single carriageway", "dual carriageway", "frontage road"]
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
    private var lastPromptAt: Date?
    private var spokenThisPass: Set<String> = []
    private var tracks: [String: ApproachTrack] = [:]

    mutating func begin(driverMode: DriverMode, tread: TreadChoice = .unsure) {
        self.driverMode = driverMode
        self.tread = tread
        streakID = nil
        streak = 0
        lastMatchAt = nil
        lastPromptAt = nil
        spokenThisPass = []
        tracks = [:]
    }

    mutating func end() {
        driverMode = nil
        streakID = nil
        streak = 0
        lastMatchAt = nil
        spokenThisPass = []
        tracks = [:]
    }

    mutating func ingest(
        fix: LocationFix,
        nearby: [Curve],
        memoryForContext: (String) -> ApproachMemory = { _ in ApproachMemory(latePasses: 0, earlyPasses: 0) },
        passesUnderRange: (String) -> Int = { _ in 0 },
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
            streak = 0
            streakID = nil
            lastMatchAt = nil
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
                completed: []
            )
        }

        let scored = score(
            fix: fix,
            nearby: nearby,
            moment: moment,
            gate: gate,
            vision: vision,
            camera: camera,
            memoryForContext: memoryForContext
        )
        let hot = scored
            .filter { $0.confidence >= DriveRules.matchConfidenceMinimum }
            .sorted { $0.distance < $1.distance }
        var ambiguous = false
        if hot.count >= 2, hot[1].distance - hot[0].distance < DriveRules.junctionGapMeters {
            ambiguous = true
        }
        if ambiguous || hot.isEmpty {
            streak = 0
            streakID = nil
            lastMatchAt = nil
        } else {
            let identifier = hot[0].curve.id
            let gap = lastMatchAt.map { moment.timeIntervalSince($0) } ?? 0
            if identifier == streakID, gap <= DriveRules.matchGapSeconds {
                streak += 1
            } else {
                streakID = identifier
                streak = 1
            }
            lastMatchAt = moment
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
                radiusFeet: item.curve.radiusFeet
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
            if braking, !ambiguous, hot.first?.curve.id == item.curve.id, track.brakingOnset == nil {
                track.brakingOnset = item.distance
                track.baseWhenBraking = item.baseLookAhead
            }
            if track.entered && !item.ahead {
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

        let focus = ambiguous ? nil : hot.first
        var prompt: DrivePrompt?
        var spokenLine: String?
        if let focus {
            let over = shouldSpeak(effectiveSpeed: focus.effective, range: focus.range)
            let quiet = suppressRepeatPrompt(
                passesUnderRange: passesUnderRange(focus.curve.id),
                effectiveSpeed: focus.effective,
                range: focus.range
            )
            let cooled = lastPromptAt.map { moment.timeIntervalSince($0) >= DriveRules.cooldownSeconds } ?? true
            let firstTime = !spokenThisPass.contains(focus.curve.id)
            let inWindow = focus.distance <= focus.lookAhead
            let ready = over && !quiet && cooled && firstTime && inWindow && streak >= DriveRules.requiredFixes
            if ready && gate.allowsSound && promptStyle == .chimeOnly && gate.allowsChime {
                prompt = .chime
            } else if ready && gate.allowsSound && promptStyle != .chimeOnly {
                prompt = .speak
                spokenLine = spokenWarning
            }
            if prompt != nil, var track = tracks[focus.curve.id] {
                track.spoke = true
                tracks[focus.curve.id] = track
                spokenThisPass.insert(focus.curve.id)
                lastPromptAt = moment
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
            screeningRange: focus?.range
        )
    }

    private func score(
        fix: LocationFix,
        nearby: [Curve],
        moment: Date,
        gate: DriveGate,
        vision: VisionCaution,
        camera: CameraEvidence?,
        memoryForContext: (String) -> ApproachMemory
    ) -> [ScoredCurve] {
        let hour = Calendar.current.component(.hour, from: moment)
        let visionUsed = gate.allowsCamera
            ? vision
            : VisionCaution(standingWaterOrSnow: false, severeUnevenOnPaved: false)
        let cameraUsed = gate.allowsCamera ? camera : nil
        let speed = max(0, fix.speedMps)
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
            let fused = fuseSurface(fileLabel: curve.surface, camera: cameraUsed, threshold: DriveRules.cameraConfidence)
            let range = screeningRange(radiusFeet: curve.radiusFeet, surface: fused.0, tread: tread)
            let effective = effectiveSpeedMPH(speedMps: speed, accuracyMps: max(0, fix.speedAccuracyMps))
            let key = approachContextKey(surface: fused.0, radiusFeet: curve.radiusFeet, hour: hour)
            let memory = memoryForContext(key)
            let base = baseLookAheadMeters(speedMps: speed)
            let extended = lookAheadMeters(speedMps: speed, memory: memory, vision: visionUsed)
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
            brakingDistanceMeters: track.brakingOnset
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
    private var horizontalGs: [Double] = []
    private var lastSpeedSample: (speed: Double, time: Date)?
    private var previousLocation: CLLocation?
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
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.activityType = .automotiveNavigation
        locationManager.distanceFilter = kCLDistanceFilterNone
        motionManager.deviceMotionUpdateInterval = 0.01
    }

    /// Opens the bundled curve file. Does not query every row, load Core ML, or start sensors.
    static func bundled() throws -> TripEngine {
        let url = try BundledCurves.prepareWritableCopy()
        return TripEngine(
            store: try SQLiteCurveStore(databaseURL: url),
            passLog: try PassLog(databaseURL: url),
            speech: SpeechPrompt()
        )
    }

    func beginTrip(driverMode: DriverMode, at date: Date = Date(), startSensors: Bool = true) throws {
        let reported = TreadStore.choice ?? .unsure
        tread = reported
        matcher.begin(driverMode: driverMode, tread: reported)
        tripID = try passLog.startTrip(mode: driverMode, at: date, notes: nil)
        previousLocation = nil
        paused = false
        latestVision = VisionCaution(standingWaterOrSnow: false, severeUnevenOnPaved: false)
        latestCamera = nil
        cameraAcceptedAt = nil
        snapshot.driverMode = driverMode
        snapshot.tripID = tripID
        snapshot.paused = false
        sensorsWanted = startSensors
        guard startSensors else { return }
        startSensorsIfNeeded()
    }

    func endTrip() {
        paused = false
        locationManager.stopUpdatingLocation()
        if motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
        }
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
        locationManager.stopUpdatingLocation()
        if motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
        }
        snapshot.paused = true
    }

    func resume() {
        guard matcher.driverMode != nil else { return }
        paused = false
        snapshot.paused = false
        guard sensorsWanted else { return }
        startSensorsIfNeeded()
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
        let nearby = explicit ?? store.curves(
            nearLatitude: fix.latitude,
            longitude: fix.longitude,
            radiusMeters: DriveRules.searchRadiusMeters
        )
        let update = matcher.ingest(
            fix: fix,
            nearby: nearby,
            memoryForContext: { key in
                (try? self.passLog.memory(for: key)) ?? ApproachMemory(latePasses: 0, earlyPasses: 0)
            },
            passesUnderRange: { identifier in
                (try? self.passLog.passesUnderRange(curveID: identifier)) ?? 0
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
                try? speech.speakWarning()
            case .chime:
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

    /// Reads this trip's rows before the caller clears the trip id.
    func debrief(curves: SQLiteCurveStore) throws -> TripScreenDebrief {
        guard let tripID else { return TripScreenDebrief() }
        return try LiveTripDebrief.make(tripID: tripID, log: passLog, curves: curves)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard tripID != nil, !paused, let location = locations.last else { return }
        if let previous = previousLocation,
           location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 50 {
            TreadStore.addMeters(location.distance(from: previous))
        }
        previousLocation = location
        let fix = LocationFix(location)
        let braking = detectBraking(fix)
        handle(fix: fix, braking: braking, now: Date())
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard tripID != nil, !paused else { return }
        enableBackgroundUpdatesIfAuthorized()
    }

    deinit {
        locationManager.stopUpdatingLocation()
        motionManager.stopDeviceMotionUpdates()
    }

    private func startSensorsIfNeeded() {
        locationManager.pausesLocationUpdatesAutomatically = false
        enableBackgroundUpdatesIfAuthorized()
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        startMotion()
    }

    private func enableBackgroundUpdatesIfAuthorized() {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.allowsBackgroundLocationUpdates = true
            locationManager.showsBackgroundLocationIndicator = true
        default:
            break
        }
    }

    private func startMotion() {
        guard motionManager.isDeviceMotionAvailable, !motionManager.isDeviceMotionActive else { return }
        motionManager.deviceMotionUpdateInterval = 0.01
        motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: motionQueue) { [weak self] motion, _ in
            guard let motion else { return }
            let horizontal = hypot(motion.userAcceleration.x, motion.userAcceleration.y)
            DispatchQueue.main.async { [weak self] in
                self?.noteHorizontalG(horizontal)
            }
        }
    }

    private func noteHorizontalG(_ value: Double) {
        horizontalGs.append(value)
        if horizontalGs.count > 10 {
            horizontalGs.removeFirst()
        }
    }

    private func detectBraking(_ fix: LocationFix) -> Bool {
        defer { lastSpeedSample = (fix.speedMps, fix.timestamp) }
        guard fix.speedMps >= 0, let previous = lastSpeedSample, previous.speed >= 0 else { return false }
        let dt = fix.timestamp.timeIntervalSince(previous.time)
        guard dt > 0.2, dt < 5 else { return false }
        let deceleration = (previous.speed - fix.speedMps) / dt
        let meanG = horizontalGs.isEmpty ? 0 : horizontalGs.reduce(0, +) / Double(horizontalGs.count)
        if meanG >= DriveRules.brakingGs && deceleration >= DriveRules.brakingDeceleration {
            return true
        }
        if !motionManager.isDeviceMotionActive && deceleration >= DriveRules.gpsOnlyDeceleration {
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
