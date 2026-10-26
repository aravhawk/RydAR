import AVFoundation
import XCTest
@testable import RydAR

final class TripEngineTests: XCTestCase {
    private let baseLat = 36.0
    private let baseLon = -94.0

    func testABackgroundAlertUsesVibrationAndAnOnScreenAlertUsesTheTapticEngine() {
        XCTAssertEqual(hapticRoute(appIsActive: true, hardwareSupportsHaptics: true), .taptic)
        XCTAssertEqual(hapticRoute(appIsActive: false, hardwareSupportsHaptics: true), .vibration)
        XCTAssertEqual(hapticRoute(appIsActive: true, hardwareSupportsHaptics: false), .vibration)
    }

    func testAParkedFixIsStandingStillRatherThanMissing() {
        let now = Date()
        let still = LocationFix(
            latitude: baseLat, longitude: baseLon, speedMps: -1, speedAccuracyMps: -1,
            courseDegrees: -1, horizontalAccuracyMeters: 5, timestamp: now
        )
        let lost = LocationFix(
            latitude: baseLat, longitude: baseLon, speedMps: -1, speedAccuracyMps: -1,
            courseDegrees: -1, horizontalAccuracyMeters: -1, timestamp: now
        )
        let ready = LocationFix(
            latitude: baseLat, longitude: baseLon, speedMps: 12, speedAccuracyMps: 1,
            courseDegrees: 90, horizontalAccuracyMeters: 8, timestamp: now
        )
        XCTAssertEqual(gpsStatusText(for: still, now: now), "Standing still")
        XCTAssertFalse(gpsIsGood(still, now: now))
        XCTAssertEqual(gpsStatusText(for: lost, now: now), "Waiting for location")
        XCTAssertEqual(gpsStatusText(for: ready, now: now), "GPS ready")
    }

    func testSpeechSessionUsesTheVoicePrompt() {
        XCTAssertEqual(SpeechPrompt.category, .playback)
        XCTAssertEqual(SpeechPrompt.mode, .voicePrompt)
        XCTAssertTrue(SpeechPrompt.options.contains(.duckOthers))
        XCTAssertTrue(SpeechPrompt.options.contains(.interruptSpokenAudioAndMixWithOthers))
        XCTAssertEqual(SpeechPrompt.line, "Curve ahead. Above advisory speed.")
        XCTAssertEqual(SpeechPrompt.line, spokenWarning)
        XCTAssertNil(SpeechPrompt.line.range(of: #"\d"#, options: .regularExpression))
        XCTAssertFalse(SpeechPrompt.line.lowercased().contains("safe speed"))
        XCTAssertFalse(SpeechPrompt.line.lowercased().contains("reduce speed"))
    }

    func testNothingIsPreselectedAndLocationDoesNotPause() throws {
        let harness = try makeHarness()
        XCTAssertNil(harness.engine.snapshot.driverMode)
        XCTAssertFalse(harness.engine.locationManager.pausesLocationUpdatesAutomatically)
        XCTAssertEqual(harness.engine.locationManager.desiredAccuracy, kCLLocationAccuracyBestForNavigation)
        XCTAssertEqual(harness.engine.locationManager.distanceFilter, kCLDistanceFilterNone)
        XCTAssertEqual(harness.engine.locationManager.activityType, .automotiveNavigation)
        XCTAssertEqual(harness.engine.motionManager.deviceMotionUpdateInterval, 0.01, accuracy: 0.0001)
        XCTAssertFalse(harness.engine.motionManager.isDeviceMotionActive)
        let update = harness.engine.handle(fix: fix(at: date(hour: 14)), nearby: [line(id: "c", north: 80)], now: date(hour: 14))
        XCTAssertNil(update.prompt)
        XCTAssertFalse(update.gate.allowsSound)
        XCTAssertTrue(harness.speech.spoken.isEmpty)
    }

    func testAdultSpeaksTheContractLineOnceAfterThreeFixes() throws {
        let harness = try makeHarness()
        try harness.engine.beginTrip(driverMode: .adult, at: date(hour: 14), startSensors: false)
        var last = TripUpdate(prompt: nil, spokenLine: nil, gate: driveGate(mode: .adult, speedMps: 20, dashEnabled: false, uploadOptIn: false), matchedCurveID: nil, matchConfidence: 0, matchStreak: 0, junctionAmbiguous: false, lookAheadMeters: nil, distanceMeters: nil, surface: nil, surfaceUI: nil, completed: [])
        for index in 0..<4 {
            let moment = date(hour: 14).addingTimeInterval(Double(index))
            last = harness.engine.handle(
                fix: fix(speed: 20, at: moment),
                nearby: [line(id: "c", north: 80)],
                now: moment
            )
            if index < 2 {
                XCTAssertNil(last.prompt)
            }
        }
        XCTAssertEqual(last.prompt, nil)
        XCTAssertEqual(harness.speech.spoken, [spokenWarning])
        XCTAssertEqual(harness.speech.chimes, 0)
        XCTAssertEqual(harness.speech.taps, 1)
        XCTAssertGreaterThanOrEqual(last.matchStreak, 3)
    }

    func testUnder18IsSilentWhileMoving() throws {
        let harness = try makeHarness()
        harness.engine.dashEnabled = true
        harness.engine.uploadOptIn = true
        harness.engine.promptStyle = .chimeOnly
        try harness.engine.beginTrip(driverMode: .under18, at: date(hour: 14), startSensors: false)
        let moment = date(hour: 14)
        var update = TripUpdate(prompt: nil, spokenLine: nil, gate: driveGate(mode: nil, speedMps: 0, dashEnabled: false, uploadOptIn: false), matchedCurveID: nil, matchConfidence: 0, matchStreak: 0, junctionAmbiguous: false, lookAheadMeters: nil, distanceMeters: nil, surface: nil, surfaceUI: nil, completed: [])
        for index in 0..<3 {
            let when = moment.addingTimeInterval(Double(index))
            update = harness.engine.handle(
                fix: fix(speed: 15, at: when),
                nearby: [line(id: "c", north: 80)],
                now: when
            )
        }
        XCTAssertNil(update.prompt)
        XCTAssertFalse(update.gate.allowsSound)
        XCTAssertFalse(update.gate.allowsChime)
        XCTAssertFalse(update.gate.allowsCamera)
        XCTAssertFalse(update.gate.allowsUpload)
        XCTAssertTrue(harness.speech.spoken.isEmpty)
        XCTAssertEqual(harness.speech.chimes, 0)
        XCTAssertEqual(harness.speech.taps, 0)

        let parked = harness.engine.handle(fix: fix(speed: 0, at: moment), nearby: [], now: moment)
        XCTAssertFalse(parked.gate.allowsSound)
        XCTAssertFalse(parked.gate.allowsCamera)
        XCTAssertTrue(parked.gate.allowsUpload)
    }

    func testPassengerChimeDoesNotSpeakASpeed() throws {
        let harness = try makeHarness()
        harness.engine.promptStyle = .chimeOnly
        try harness.engine.beginTrip(driverMode: .passenger, at: date(hour: 14), startSensors: false)
        for index in 0..<3 {
            let when = date(hour: 14).addingTimeInterval(Double(index))
            _ = harness.engine.handle(fix: fix(speed: 20, at: when), nearby: [line(id: "c", north: 80)], now: when)
        }
        XCTAssertTrue(harness.speech.spoken.isEmpty)
        XCTAssertEqual(harness.speech.chimes, 1)
        XCTAssertEqual(harness.speech.taps, 1)
    }

    func testLookAheadFollowsMemoryAndNeverShrinks() {
        let calm = ApproachMemory(latePasses: 0, earlyPasses: 0)
        let one = ApproachMemory(latePasses: 1, earlyPasses: 0)
        let three = ApproachMemory(latePasses: 3, earlyPasses: 0)
        let quiet = VisionCaution(standingWaterOrSnow: false, severeUnevenOnPaved: false)
        let water = VisionCaution(standingWaterOrSnow: true, severeUnevenOnPaved: false)
        let curve = line(id: "far", north: 130)
        let moment = date(hour: 14)

        let baseline = run(mode: .adult, speed: 15, curve: curve, memory: calm, vision: quiet, at: moment)
        XCTAssertNil(baseline.prompt)
        XCTAssertEqual(baseline.lookAheadMeters ?? 0, baseLookAheadMeters(speedMps: 15), accuracy: 0.01)

        let single = run(mode: .adult, speed: 15, curve: curve, memory: one, vision: quiet, at: moment)
        XCTAssertNil(single.prompt)
        XCTAssertEqual(single.lookAheadMeters ?? 0, baseLookAheadMeters(speedMps: 15), accuracy: 0.01)

        let learned = run(mode: .adult, speed: 15, curve: curve, memory: three, vision: quiet, at: moment)
        let expected = lookAheadMeters(speedMps: 15, memory: three, vision: quiet)
        XCTAssertEqual(learned.prompt, .speak)
        XCTAssertEqual(learned.spokenLine, spokenWarning)
        XCTAssertEqual(learned.lookAheadMeters ?? 0, expected, accuracy: 0.01)
        XCTAssertGreaterThan(expected, baseLookAheadMeters(speedMps: 15))

        let camera = run(mode: .adult, speed: 15, curve: curve, memory: calm, vision: water, dash: true, at: moment)
        XCTAssertEqual(camera.prompt, .speak)
        XCTAssertEqual(
            camera.lookAheadMeters ?? 0,
            lookAheadMeters(speedMps: 15, memory: calm, vision: water),
            accuracy: 0.01
        )

        let teen = run(mode: .under18, speed: 15, curve: curve, memory: calm, vision: water, dash: true, at: moment)
        XCTAssertNil(teen.prompt)
        XCTAssertEqual(teen.lookAheadMeters ?? 0, baseLookAheadMeters(speedMps: 15), accuracy: 0.01)
        XCTAssertFalse(teen.gate.allowsCamera)
    }

    func testGatesSkipBadRowsAndJunctions() {
        let moment = date(hour: 14)
        XCTAssertEqual(run(mode: .adult, speed: 20, curve: line(id: "ok", north: 80, roadClass: "State"), at: moment).prompt, .speak)
        XCTAssertNil(run(mode: .adult, speed: 20, curve: line(id: "flags", north: 80, flags: "sparse_vertices_gt25m"), at: moment).prompt)
        XCTAssertNil(run(mode: .adult, speed: 20, curve: line(id: "private", north: 80, roadClass: "Private"), at: moment).prompt)
        XCTAssertNil(run(mode: .adult, speed: 20, curve: line(id: "ramp", north: 80, roadDesign: "At-Grade Ramp"), at: moment).prompt)
        XCTAssertNil(run(mode: .adult, speed: 20, curve: line(id: "loop", north: 80, closedLoop: true), at: moment).prompt)
        XCTAssertNil(run(mode: .adult, speed: 20, curve: line(id: "hairpin", north: 80, radius: 40), at: moment).prompt)
        XCTAssertNil(run(mode: .adult, speed: 8, curve: line(id: "under", north: 80), at: moment).prompt)
        XCTAssertEqual(run(mode: .adult, speed: 10, curve: line(id: "over", north: 80), at: moment).prompt, .speak)

        var matcher = TripMatcher()
        matcher.begin(driverMode: .adult)
        let pair = [
            line(id: "left", north: 80, east: 0),
            line(id: "right", north: 80, east: 12),
        ]
        var ambiguous = TripUpdate(prompt: nil, spokenLine: nil, gate: driveGate(mode: nil, speedMps: 0, dashEnabled: false, uploadOptIn: false), matchedCurveID: nil, matchConfidence: 0, matchStreak: 0, junctionAmbiguous: false, lookAheadMeters: nil, distanceMeters: nil, surface: nil, surfaceUI: nil, completed: [])
        for index in 0..<3 {
            ambiguous = matcher.ingest(fix: fix(speed: 20, at: moment.addingTimeInterval(Double(index))), nearby: pair)
        }
        XCTAssertTrue(ambiguous.junctionAmbiguous)
        XCTAssertNil(ambiguous.prompt)
        XCTAssertNil(ambiguous.spokenLine)

        matcher = TripMatcher()
        matcher.begin(driverMode: .adult)
        var offCourse = ambiguous
        for index in 0..<3 {
            offCourse = matcher.ingest(
                fix: fix(speed: 20, course: 80, at: moment.addingTimeInterval(Double(index))),
                nearby: [line(id: "north", north: 80)]
            )
        }
        XCTAssertNil(offCourse.prompt)
        XCTAssertLessThan(offCourse.matchConfidence, 0.9)
    }

    func testCooldownAndAGapInTheFixStreak() {
        var matcher = TripMatcher()
        matcher.begin(driverMode: .adult)
        let start = date(hour: 14)
        for index in 0..<3 {
            let update = matcher.ingest(
                fix: fix(speed: 20, at: start.addingTimeInterval(Double(index))),
                nearby: [line(id: "a", north: 80)]
            )
            if index == 2 {
                XCTAssertEqual(update.prompt, .speak)
            }
        }
        var blocked = matcher.ingest(fix: fix(speed: 20, at: start), nearby: [])
        for index in 0..<3 {
            let when = start.addingTimeInterval(Double(3 + index))
            blocked = matcher.ingest(fix: fix(speed: 20, at: when), nearby: [line(id: "b", north: 80)])
        }
        XCTAssertEqual(blocked.matchStreak, 3)
        XCTAssertNil(blocked.prompt)

        var spokeAgain = false
        for index in 0..<10 {
            let when = start.addingTimeInterval(Double(6 + index))
            let update = matcher.ingest(fix: fix(speed: 20, at: when), nearby: [line(id: "b", north: 80)])
            if update.prompt == .speak {
                spokeAgain = true
                XCTAssertGreaterThanOrEqual(when.timeIntervalSince(start), 12)
                XCTAssertEqual(update.spokenLine, spokenWarning)
                break
            }
        }
        XCTAssertTrue(spokeAgain)

        matcher = TripMatcher()
        matcher.begin(driverMode: .adult)
        _ = matcher.ingest(fix: fix(speed: 20, at: start), nearby: [line(id: "c", north: 80)])
        _ = matcher.ingest(fix: fix(speed: 20, at: start.addingTimeInterval(1)), nearby: [line(id: "c", north: 80)])
        let reset = matcher.ingest(fix: fix(speed: 20, at: start.addingTimeInterval(30)), nearby: [line(id: "c", north: 80)])
        XCTAssertEqual(reset.matchStreak, 1)
        XCTAssertNil(reset.prompt)
    }

    func testRepeatUnderRangeStaysQuietAndOverRangeStillSpeaks() {
        let moment = date(hour: 14)
        let quiet = run(mode: .adult, speed: 8, curve: line(id: "known", north: 80), passesUnder: 3, at: moment)
        XCTAssertNil(quiet.prompt)
        let still = run(mode: .adult, speed: 12, curve: line(id: "known", north: 80), passesUnder: 3, at: moment)
        XCTAssertEqual(still.prompt, .speak)
        XCTAssertEqual(still.spokenLine, "Curve ahead. Above advisory speed.")
    }

    func testLoggedMemoryLengthensTheNextApproach() throws {
        let harness = try makeHarness()
        let moment = date(hour: 14)
        let key = approachContextKey(surface: .paved, radiusFeet: 200, hour: 14)
        let seedTrip = try harness.log.startTrip(mode: .adult, at: moment)
        for _ in 0..<3 {
            try harness.log.record(
                CompletedPass(
                    curveID: "seed",
                    direction: "N",
                    effectiveSpeedMPH: 40,
                    vLoMPH: 19,
                    vHiMPH: 23,
                    spoke: true,
                    hourBucket: 14,
                    late: true,
                    surfaceUsed: .paved,
                    radiusBand: "150-300",
                    lookAheadMeters: 140,
                    contextKey: key
                ),
                tripID: seedTrip
            )
        }
        XCTAssertEqual(try harness.log.memory(for: key).latePasses, 3)
        try harness.engine.beginTrip(driverMode: .adult, at: moment, startSensors: false)
        var update = TripUpdate(prompt: nil, spokenLine: nil, gate: driveGate(mode: .adult, speedMps: 15, dashEnabled: false, uploadOptIn: false), matchedCurveID: nil, matchConfidence: 0, matchStreak: 0, junctionAmbiguous: false, lookAheadMeters: nil, distanceMeters: nil, surface: nil, surfaceUI: nil, completed: [])
        for index in 0..<3 {
            let when = moment.addingTimeInterval(Double(index))
            update = harness.engine.handle(
                fix: fix(speed: 15, speedAccuracy: 0, at: when),
                nearby: [line(id: "far", north: 130)],
                now: when
            )
        }
        let expected = lookAheadMeters(
            speedMps: 15,
            memory: ApproachMemory(latePasses: 3, earlyPasses: 0),
            vision: VisionCaution(standingWaterOrSnow: false, severeUnevenOnPaved: false)
        )
        XCTAssertEqual(update.lookAheadMeters ?? 0, expected, accuracy: 0.01)
        XCTAssertGreaterThan(expected, baseLookAheadMeters(speedMps: 15))
        XCTAssertEqual(update.prompt, .speak)
        XCTAssertEqual(harness.speech.spoken, [spokenWarning])
    }

    func testALatePassIsWrittenOnceTheCurveIsBehind() throws {
        let harness = try makeHarness()
        let start = date(hour: 14)
        try harness.engine.beginTrip(driverMode: .adult, at: start, startSensors: false)
        let curve = line(id: "bend", north: 200, length: 40)
        var prompts = 0
        var completed = 0
        var north = 0.0
        var last = TripUpdate(prompt: nil, spokenLine: nil, gate: driveGate(mode: .adult, speedMps: 20, dashEnabled: false, uploadOptIn: false), matchedCurveID: nil, matchConfidence: 0, matchStreak: 0, junctionAmbiguous: false, lookAheadMeters: nil, distanceMeters: nil, surface: nil, surfaceUI: nil, completed: [])
        for index in 0..<20 {
            let when = start.addingTimeInterval(Double(index))
            let distance = last.distanceMeters ?? 200
            last = harness.engine.handle(
                fix: fix(north: north, speed: 20, speedAccuracy: 0, at: when),
                nearby: [curve],
                braking: distance < 130 && distance > 50,
                now: when
            )
            if last.prompt != nil { prompts += 1 }
            completed += last.completed.count
            north += 20
            if completed > 0 { break }
        }
        XCTAssertEqual(prompts, 1, "distance \(last.distanceMeters ?? -1) streak \(last.matchStreak)")
        XCTAssertEqual(completed, 1, "distance \(last.distanceMeters ?? -1) streak \(last.matchStreak)")
        let tripID = try XCTUnwrap(harness.engine.snapshot.tripID)
        let rows = try harness.log.passes(forTrip: tripID)
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows[0].pass.late)
        XCTAssertTrue(rows[0].pass.spoke)
        XCTAssertEqual(rows[0].pass.curveID, "bend")
        XCTAssertEqual(harness.speech.spoken, [spokenWarning])
        let key = approachContextKey(surface: .paved, radiusFeet: 200, hour: 14)
        XCTAssertEqual(rows[0].pass.contextKey, key)
        XCTAssertEqual(try harness.log.memory(for: key).latePasses, 1)
    }

    private func run(
        mode: DriverMode,
        speed: Double,
        curve: Curve,
        memory: ApproachMemory = ApproachMemory(latePasses: 0, earlyPasses: 0),
        vision: VisionCaution = VisionCaution(standingWaterOrSnow: false, severeUnevenOnPaved: false),
        dash: Bool = false,
        passesUnder: Int = 0,
        at moment: Date
    ) -> TripUpdate {
        var matcher = TripMatcher()
        matcher.begin(driverMode: mode)
        matcher.dashEnabled = dash
        var update = TripUpdate(prompt: nil, spokenLine: nil, gate: driveGate(mode: mode, speedMps: speed, dashEnabled: dash, uploadOptIn: false), matchedCurveID: nil, matchConfidence: 0, matchStreak: 0, junctionAmbiguous: false, lookAheadMeters: nil, distanceMeters: nil, surface: nil, surfaceUI: nil, completed: [])
        for index in 0..<3 {
            update = matcher.ingest(
                fix: fix(speed: speed, speedAccuracy: 0, at: moment.addingTimeInterval(Double(index))),
                nearby: [curve],
                memoryForContext: { _ in memory },
                passesUnderRange: { _ in passesUnder },
                vision: vision,
                now: moment.addingTimeInterval(Double(index))
            )
        }
        return update
    }

    private func line(
        id: String,
        north: Double,
        east: Double = 0,
        length: Double = 40,
        radius: Double = 200,
        surface: RoadSurface = .paved,
        roadClass: String = "County",
        roadDesign: String = "Single Carriageway",
        flags: String = "",
        closedLoop: Bool = false
    ) -> Curve {
        var points: [MapPoint] = []
        var cursor = north
        while cursor <= north + length + 0.01 {
            points.append(mapPoint(north: cursor, east: east))
            cursor += 10
        }
        let latitudes = points.map(\.latitude)
        let longitudes = points.map(\.longitude)
        return Curve(
            id: id,
            county: "Benton",
            roadName: "Test Rd",
            surface: surface,
            radiusFeet: radius,
            deflectionDegrees: 45,
            qualityFlags: flags,
            roadClass: roadClass,
            roadDesign: roadDesign,
            closedLoop: closedLoop,
            latitude: points[0].latitude,
            longitude: points[0].longitude,
            minLatitude: latitudes.min() ?? baseLat,
            maxLatitude: latitudes.max() ?? baseLat,
            minLongitude: longitudes.min() ?? baseLon,
            maxLongitude: longitudes.max() ?? baseLon,
            coordinates: points
        )
    }

    private func fix(
        north: Double = 0,
        speed: Double = 20,
        course: Double = 0,
        accuracy: Double = 5,
        speedAccuracy: Double = 0.5,
        at moment: Date
    ) -> LocationFix {
        let point = mapPoint(north: north, east: 0)
        return LocationFix(
            latitude: point.latitude,
            longitude: point.longitude,
            speedMps: speed,
            speedAccuracyMps: speedAccuracy,
            courseDegrees: course,
            horizontalAccuracyMeters: accuracy,
            timestamp: moment
        )
    }

    private func mapPoint(north: Double, east: Double) -> MapPoint {
        MapPoint(
            longitude: baseLon + east / Geo.metersPerDegreeLongitude(baseLat),
            latitude: baseLat + north / Geo.metersPerDegreeLatitude
        )
    }

    private func date(hour: Int) -> Date {
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 10
        parts.day = 24
        parts.hour = hour
        parts.minute = 0
        parts.second = 0
        return Calendar.current.date(from: parts) ?? Date(timeIntervalSince1970: 0)
    }

    private func makeHarness() throws -> (engine: TripEngine, speech: SpyPrompt, log: PassLog) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("engine-\(UUID().uuidString).sqlite")
        let log = try PassLog(databaseURL: url)
        let speech = SpyPrompt()
        let engine = TripEngine(store: EmptyCurveStore(), passLog: log, speech: speech)
        return (engine, speech, log)
    }

    func testFifteenMilesAnHourOnAGentleCurveStaysQuietAndShowsTheSpeed() {
        let speed = 15 / 2.23694
        let update = run(
            mode: .adult,
            speed: speed,
            curve: line(id: "gentle", north: 80, radius: 400),
            at: Date()
        )
        XCTAssertNil(update.prompt)
        XCTAssertEqual(update.measuredSpeedMPH ?? -1, 15, accuracy: 0.2)
        if let low = update.screeningRange?.low {
            XCTAssertLessThan(update.promptSpeedMPH ?? -1, low)
        }
    }

    func testARampClassWithABlankDesignStaysQuiet() {
        XCTAssertFalse(canWarn(on: line(id: "class-ramp", north: 80, roadClass: "Ramp", roadDesign: "")))
        XCTAssertTrue(canWarn(on: line(id: "county", north: 80, roadClass: "County", roadDesign: "")))
    }

    func testBlankAndAbbreviatedDesignsAreNotRamps() {
        XCTAssertFalse(isRampDesign(""))
        XCTAssertFalse(isRampDesign("SC"))
        XCTAssertFalse(isRampDesign("DC"))
        XCTAssertFalse(isRampDesign("Dual Carriage"))
        XCTAssertTrue(isRampDesign("At-Grade Ramp"))
        XCTAssertTrue(isRampDesign("Driveway"))
    }
}

private final class EmptyCurveStore: CurveStore {
    func curves(nearLatitude latitude: Double, longitude: Double, radiusMeters: Double) -> [Curve] { [] }
}

private final class SpyPrompt: PromptPlaying {
    var spoken: [String] = []
    var chimes = 0
    var taps = 0
    func speakWarning() throws { spoken.append(spokenWarning) }
    func playChime() throws { chimes += 1 }
    func playCurveTap() { taps += 1 }
}
