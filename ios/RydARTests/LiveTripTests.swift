import XCTest
@testable import RydAR

@MainActor
final class LiveTripTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: DashPreference.key)
    }

    func testStartStoresUploadAndTurnsDashOn() throws {
        let harness = try makeHarness()
        harness.bridge.start(mode: .adult, uploadOptIn: true)
        XCTAssertTrue(harness.engine.uploadOptIn)
        XCTAssertTrue(harness.engine.dashEnabled)
        XCTAssertNotNil(harness.engine.snapshot.tripID)
        XCTAssertFalse(harness.engine.locationManager.pausesLocationUpdatesAutomatically)
        let kept = harness.engine.snapshot.tripID
        harness.bridge.onUploadPreference?(false)
        XCTAssertFalse(harness.engine.uploadOptIn)
        XCTAssertEqual(harness.engine.snapshot.tripID, kept)
        harness.bridge.onUploadPreference?(true)
        XCTAssertEqual(harness.engine.snapshot.tripID, kept)
    }

    func testUnder18StartSkipsTheCameraAndKeepsSharing() throws {
        let harness = try makeHarness()
        harness.bridge.start(mode: .under18, uploadOptIn: true)
        XCTAssertTrue(harness.engine.uploadOptIn)
        XCTAssertFalse(harness.engine.dashEnabled)
        let gate = driveGate(mode: .under18, speedMps: 15, dashEnabled: harness.engine.dashEnabled, uploadOptIn: harness.engine.uploadOptIn)
        XCTAssertFalse(gate.allowsCamera)
        XCTAssertTrue(gate.allowsSound)
        XCTAssertTrue(gate.allowsUpload)
        let start = date(hour: 14)
        for index in 0..<3 {
            let when = start.addingTimeInterval(Double(index))
            _ = harness.engine.handle(fix: fix(speed: 20, at: when), nearby: [line(id: "c", north: 80)], now: when)
        }
        XCTAssertEqual(harness.speech.spoken.count, 1)
        XCTAssertNil(harness.bridge.drive.nextCurve)
        XCTAssertNil(harness.bridge.drive.distanceMeters)
        XCTAssertNil(harness.bridge.drive.advisoryNotice)
    }

    func testLocationUpdatePublishesTheMatchedCurveOnTheBridge() throws {
        let harness = try makeHarness()
        let start = date(hour: 14)
        harness.bridge.start(mode: .adult, uploadOptIn: false)
        let curve = line(id: "c", north: 80)
        for index in 0..<3 {
            let when = start.addingTimeInterval(Double(index))
            harness.engine.handle(fix: fix(speed: 20, at: when), nearby: [curve], now: when)
        }
        XCTAssertEqual(harness.bridge.drive.nextCurve?.id, "c")
        XCTAssertNotNil(harness.bridge.drive.distanceMeters)
        XCTAssertEqual(harness.bridge.drive.gpsStatus, "GPS ready")
        XCTAssertNil(harness.bridge.drive.placeTitle)
        XCTAssertEqual(harness.bridge.drive.measuredSpeedMPH ?? -1, 20 * 2.23694, accuracy: 0.1)
        XCTAssertFalse(harness.bridge.drive.isPaused)
        XCTAssertEqual(harness.bridge.drive.cameraStatus, "Using road records")
        XCTAssertEqual(harness.bridge.drive.tripTitle, "Camera on")
        XCTAssertEqual(
            harness.bridge.drive.screeningRange,
            screeningRange(radiusFeet: 200, surface: .paved)
        )
        XCTAssertNil(harness.bridge.drive.cameraEvidence)
        XCTAssertEqual(harness.bridge.drive.cameraThreshold, DriveRules.materialConfidence)
        XCTAssertEqual(harness.speech.spoken, [spokenCurveWarning(advisoryMPH: advisorySpeedMPH(screeningRange(radiusFeet: 200, surface: .paved)))])
        XCTAssertEqual(harness.bridge.drive.advisoryNotice, harness.speech.spoken.first)
        XCTAssertEqual(harness.bridge.drive.advisoryWarning, true)
        XCTAssertNotNil(harness.bridge.drive.latitude)
        XCTAssertNotNil(harness.bridge.drive.longitude)
        harness.bridge.setPaused(true)
        XCTAssertTrue(harness.bridge.drive.isPaused)
        XCTAssertEqual(harness.bridge.drive.nextCurve?.id, "c")
        XCTAssertEqual(harness.bridge.drive.gpsStatus, "GPS ready")
    }

    func testStandingStillPublishesThePlaceAndZeroMph() throws {
        let geocoder = ScriptedPlaceGeocoder()
        geocoder.parts = PlaceParts(thoroughfare: "SE 14th St", locality: "Bentonville", administrativeArea: "AR")
        let harness = try makeHarness(places: RiderPlaceLookup(geocoder: geocoder))
        harness.bridge.start(mode: .adult, uploadOptIn: false)
        let now = date(hour: 14)
        let still = LocationFix(
            latitude: baseLat, longitude: baseLon, speedMps: -1, speedAccuracyMps: -1,
            courseDegrees: -1, horizontalAccuracyMeters: 5, timestamp: now
        )
        harness.engine.handle(fix: still, nearby: [], now: now)
        XCTAssertEqual(geocoder.requests, 1)
        XCTAssertEqual(harness.bridge.drive.gpsStatus, "Standing still")
        XCTAssertEqual(harness.bridge.drive.measuredSpeedMPH, 0)
        XCTAssertEqual(harness.bridge.drive.placeTitle, "SE 14th St")
        XCTAssertEqual(harness.bridge.drive.placeDetail, "Bentonville, AR")
        let readout = driveReadout(
            hasCurve: harness.bridge.drive.nextCurve != nil,
            roadName: harness.bridge.drive.nextCurve?.roadName,
            gpsStatus: harness.bridge.drive.gpsStatus,
            measuredSpeedMPH: harness.bridge.drive.measuredSpeedMPH,
            placeTitle: harness.bridge.drive.placeTitle,
            placeDetail: harness.bridge.drive.placeDetail
        )
        XCTAssertEqual(readout.headline, "SE 14th St")
        XCTAssertEqual(readout.locationPin, "Bentonville, AR")
        XCTAssertEqual(readout.speedMPH, 0)
        XCTAssertFalse(readout.headline.contains("Standing still"))
        XCTAssertFalse(readout.locationPin?.contains("Standing still") ?? false)
        XCTAssertFalse(readout.headline.contains("Speed unknown"))

        harness.engine.handle(fix: still, nearby: [], now: now.addingTimeInterval(1))
        XCTAssertEqual(geocoder.requests, 1)

        harness.engine.handle(fix: fix(speed: 20, at: now.addingTimeInterval(2)), nearby: [], now: now.addingTimeInterval(2))
        XCTAssertEqual(harness.bridge.drive.gpsStatus, "GPS ready")
        XCTAssertNil(harness.bridge.drive.placeTitle)
        XCTAssertNil(harness.bridge.drive.placeDetail)
        XCTAssertGreaterThan(harness.bridge.drive.measuredSpeedMPH ?? 0, 10)
    }

    func testAShortLocationGapDoesNotCountAsALostSignal() {
        let now = date(hour: 14)
        XCTAssertTrue(DriveDisplayHold.canShow("GPS ready"))
        XCTAssertTrue(DriveDisplayHold.canShow("Standing still"))
        XCTAssertFalse(DriveDisplayHold.canShow("Waiting for location"))
        XCTAssertFalse(DriveDisplayHold.canShow("No GPS signal. Warnings paused."))
        XCTAssertFalse(DriveDisplayHold.signalIsMissing(lastFix: now, now: now.addingTimeInterval(4)))
        XCTAssertFalse(DriveDisplayHold.signalIsMissing(lastFix: now, now: now.addingTimeInterval(10)))
        XCTAssertTrue(DriveDisplayHold.signalIsMissing(lastFix: now, now: now.addingTimeInterval(16)))
    }

    func testALiveWarningSpeaks() throws {
        let harness = try makeHarness()
        let start = date(hour: 14)
        harness.bridge.start(mode: .adult, uploadOptIn: false)
        let curve = line(id: "c", north: 80)
        for index in 0..<3 {
            let when = start.addingTimeInterval(Double(index))
            harness.engine.handle(fix: fix(speed: 20, at: when), nearby: [curve], now: when)
        }
        XCTAssertEqual(harness.speech.spoken.count, 1)
    }

    func testPauseAndFinishPublishSavedRowsBeforeTheTripIdClears() throws {
        let harness = try makeHarness()
        let key = approachContextKey(surface: .paved, radiusFeet: 200, hour: 14)
        let seed = try harness.log.startTrip(mode: .adult, at: date(hour: 14))
        for _ in 0..<3 {
            try harness.log.record(latePass(key: key), tripID: seed)
        }
        let start = date(hour: 14)
        harness.bridge.start(mode: .adult, uploadOptIn: false)
        harness.bridge.setPaused(true)
        XCTAssertTrue(harness.bridge.drive.isPaused)
        XCTAssertTrue(harness.engine.snapshot.paused)
        harness.bridge.setPaused(false)
        XCTAssertFalse(harness.engine.snapshot.paused)
        let curve = line(id: "bend", north: 200, length: 40)
        try insertCurve(harness.writer, curve)
        var completed = 0
        var north = 0.0
        var lastDistance = 200.0
        for index in 0..<20 {
            let when = start.addingTimeInterval(Double(index))
            let update = harness.engine.handle(
                fix: fix(north: north, speed: 20, speedAccuracy: 0, at: when),
                nearby: [curve],
                braking: lastDistance < 130 && lastDistance > 50,
                now: when
            )
            completed += update.completed.count
            lastDistance = update.distanceMeters ?? lastDistance
            north += 20
            if completed > 0 { break }
        }
        XCTAssertEqual(completed, 1)
        let tripID = try XCTUnwrap(harness.engine.snapshot.tripID)
        harness.bridge.finish()
        XCTAssertNil(harness.engine.snapshot.tripID)
        XCTAssertEqual(harness.bridge.debrief.tripID, tripID)
        XCTAssertEqual(harness.bridge.debrief.passes.count, 1)
        let pass = try XCTUnwrap(harness.bridge.debrief.passes.first)
        XCTAssertEqual(pass.curve.roadName, "Test Rd")
        XCTAssertEqual(pass.surfaceUsed, .paved)
        XCTAssertGreaterThan(pass.range.low, 0)
        XCTAssertGreaterThan(pass.range.high, pass.range.low)
        XCTAssertEqual(harness.bridge.debrief.lateContexts.count, 1)
        XCTAssertTrue(harness.bridge.debrief.lateContexts[0].movesPromptEarlier)
    }

    func testOptInSendsOnePassAndALaterToggleDoesNotReplay() throws {
        let spy = SpyUpload()
        let harness = try makeHarness(uploader: spy)
        let start = date(hour: 14)
        harness.bridge.start(mode: .adult, uploadOptIn: true)
        let curve = line(id: "007-2-3", north: 200, length: 40)
        try insertCurve(harness.writer, curve)
        var completed = 0
        var north = 0.0
        for index in 0..<20 {
            let when = start.addingTimeInterval(Double(index))
            let update = harness.engine.handle(
                fix: fix(north: north, speed: 20, speedAccuracy: 0, at: when),
                nearby: [curve],
                now: when
            )
            completed += update.completed.count
            north += 20
            if completed > 0 { break }
        }
        XCTAssertEqual(completed, 1)
        XCTAssertEqual(spy.sent.count, 0, "passes wait for the end of the trip")
        harness.bridge.finish()
        XCTAssertEqual(spy.sent.count, 1)
        XCTAssertEqual(spy.sent[0].curve_id, "007-2-3")
        XCTAssertEqual(spy.sent[0].direction, "N")
        XCTAssertEqual(spy.sent[0].speed_band_mph, 20 * 2.23694, accuracy: 0.001)
        XCTAssertEqual(spy.sent[0].hour_bucket, 14)
        harness.bridge.onUploadPreference?(true)
        XCTAssertEqual(spy.sent.count, 1)
    }

    func testUnder18CompletesAPassAndSharesItWhenSharingIsOn() throws {
        let spy = SpyUpload()
        let harness = try makeHarness(uploader: spy)
        harness.bridge.start(mode: .under18, uploadOptIn: true)
        let curve = line(id: "007-2-3", north: 200, length: 40)
        var completed = 0
        var north = 0.0
        let start = date(hour: 14)
        for index in 0..<20 {
            let when = start.addingTimeInterval(Double(index))
            let update = harness.engine.handle(
                fix: fix(north: north, speed: 20, speedAccuracy: 0, at: when),
                nearby: [curve],
                now: when
            )
            completed += update.completed.count
            north += 20
            if completed > 0 { break }
        }
        XCTAssertEqual(completed, 1)
        XCTAssertTrue(spy.sent.isEmpty, "passes wait for the end of the trip")
        harness.bridge.finish()
        XCTAssertEqual(spy.sent.count, 1)
        XCTAssertEqual(spy.sent[0].curve_id, "007-2-3")
        XCTAssertNil(harness.bridge.drive.nextCurve)
    }

    func testDeleteClearsPassHistoryAndKeepsTheCurveTable() throws {
        let harness = try makeHarness()
        harness.bridge.start(mode: .adult, uploadOptIn: true)
        let curve = line(id: "kept", north: 10)
        try insertCurve(harness.writer, curve)
        try harness.log.record(latePass(key: "paved|150-300|day"), tripID: try XCTUnwrap(harness.engine.snapshot.tripID))
        try harness.bridge.deleteAllData()
        XCTAssertNil(harness.engine.snapshot.tripID)
        XCTAssertFalse(harness.engine.uploadOptIn)
        XCTAssertTrue(try harness.log.passes(forTrip: "anything").isEmpty)
        XCTAssertEqual(try harness.log.contexts().count, 0)
        XCTAssertEqual(harness.curves.curve(id: "kept")?.roadName, "Test Rd")
    }

    private func makeHarness(
        uploader: PassSending = PassUpload(endpoint: nil),
        places: RiderPlaceLookup = RiderPlaceLookup()
    ) throws -> Harness {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("live-\(UUID().uuidString).sqlite")
        let writer = try SQLiteConnection(url: url, readonly: false)
        try writer.execute(
            """
            CREATE TABLE curves (
              id TEXT PRIMARY KEY,
              county TEXT NOT NULL,
              road_name TEXT,
              surface TEXT NOT NULL,
              radius_ft REAL NOT NULL,
              deflection_deg REAL,
              rd_class TEXT,
              rd_design TEXT,
              closed_loop INTEGER NOT NULL DEFAULT 0,
              quality_flags TEXT NOT NULL DEFAULT '',
              lat REAL NOT NULL,
              lon REAL NOT NULL,
              min_lat REAL NOT NULL,
              max_lat REAL NOT NULL,
              min_lon REAL NOT NULL,
              max_lon REAL NOT NULL,
              coordinates_json TEXT NOT NULL
            );
            """
        )
        let log = try PassLog(databaseURL: url)
        let curves = try SQLiteCurveStore(databaseURL: url)
        let speech = SpySpeech()
        let engine = TripEngine(store: curves, passLog: log, speech: speech)
        let bridge = TripScreenBridge()
        let session = LiveTripSession(
            engine: engine,
            bridge: bridge,
            curves: curves,
            startSensors: false,
            uploader: uploader,
            places: places
        )
        return Harness(url: url, writer: writer, log: log, curves: curves, engine: engine, bridge: bridge, speech: speech, session: session)
    }

    private func latePass(key: String) -> CompletedPass {
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
        )
    }

    private func insertCurve(_ connection: SQLiteConnection, _ curve: Curve) throws {
        let pairs = curve.coordinates.map { [$0.longitude, $0.latitude] }
        let data = try JSONSerialization.data(withJSONObject: pairs)
        let json = String(decoding: data, as: UTF8.self)
        try connection.run(
            """
            INSERT INTO curves (
              id, county, road_name, surface, radius_ft, deflection_deg, rd_class, rd_design,
              closed_loop, quality_flags, lat, lon, min_lat, max_lat, min_lon, max_lon, coordinates_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        ) { statement in
            connection.bind(statement, 1, curve.id)
            connection.bind(statement, 2, curve.county)
            connection.bind(statement, 3, curve.roadName)
            connection.bind(statement, 4, curve.surface.rawValue)
            connection.bind(statement, 5, curve.radiusFeet)
            connection.bind(statement, 6, curve.deflectionDegrees)
            connection.bind(statement, 7, curve.roadClass)
            connection.bind(statement, 8, curve.roadDesign)
            connection.bind(statement, 9, curve.closedLoop ? 1 : 0)
            connection.bind(statement, 10, curve.qualityFlags)
            connection.bind(statement, 11, curve.latitude)
            connection.bind(statement, 12, curve.longitude)
            connection.bind(statement, 13, curve.minLatitude)
            connection.bind(statement, 14, curve.maxLatitude)
            connection.bind(statement, 15, curve.minLongitude)
            connection.bind(statement, 16, curve.maxLongitude)
            connection.bind(statement, 17, json)
        }
    }

    private let baseLat = 36.0
    private let baseLon = -94.0

    private func line(id: String, north: Double, length: Double = 40) -> Curve {
        var points: [MapPoint] = []
        var cursor = north
        while cursor <= north + length + 0.01 {
            points.append(MapPoint(
                longitude: baseLon,
                latitude: baseLat + cursor / Geo.metersPerDegreeLatitude
            ))
            cursor += 10
        }
        let latitudes = points.map(\.latitude)
        return Curve(
            id: id,
            county: "Benton",
            roadName: "Test Rd",
            surface: .paved,
            radiusFeet: 200,
            deflectionDegrees: 45,
            qualityFlags: "",
            roadClass: "County",
            roadDesign: "Single Carriageway",
            closedLoop: false,
            latitude: points[0].latitude,
            longitude: points[0].longitude,
            minLatitude: latitudes.min() ?? baseLat,
            maxLatitude: latitudes.max() ?? baseLat,
            minLongitude: baseLon,
            maxLongitude: baseLon,
            coordinates: points
        )
    }

    private func fix(north: Double = 0, speed: Double, speedAccuracy: Double = 0.5, at moment: Date) -> LocationFix {
        LocationFix(
            latitude: baseLat + north / Geo.metersPerDegreeLatitude,
            longitude: baseLon,
            speedMps: speed,
            speedAccuracyMps: speedAccuracy,
            courseDegrees: 0,
            horizontalAccuracyMeters: 5,
            timestamp: moment
        )
    }

    private func date(hour: Int) -> Date {
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 10
        parts.day = 24
        parts.hour = hour
        return Calendar.current.date(from: parts) ?? Date(timeIntervalSince1970: 0)
    }
}

private struct Harness {
    var url: URL
    var writer: SQLiteConnection
    var log: PassLog
    var curves: SQLiteCurveStore
    var engine: TripEngine
    var bridge: TripScreenBridge
    var speech: SpySpeech
    var session: LiveTripSession
}

private final class SpyUpload: PassSending {
    var sent: [AnonymousPassBody] = []
    func send(_ body: AnonymousPassBody) { sent.append(body) }
}

private final class SpySpeech: PromptPlaying {
    var spoken: [String] = []
    func speakWarning(_ line: String) throws { spoken.append(line) }
}
