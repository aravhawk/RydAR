import CoreML
import XCTest
@testable import RydAR

@MainActor
final class DashTests: XCTestCase {
    private var sessions: [LiveTripSession] = []

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: DashPreference.key)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: DashPreference.key)
        super.tearDown()
    }

    func testAgreementNeedsFourOfSixAtTheCameraThreshold() {
        var heads = DashConsensus()
        let unpaved: [Float] = [0.02, 0.95, 0.03]
        let paved: [Float] = [0.97, 0.02, 0.01]
        var accepted: DashVote?
        for index in 0..<6 {
            accepted = heads.observe(index < 4 ? unpaved : paved)
            if index < 5 {
                XCTAssertNil(accepted)
            }
        }
        XCTAssertEqual(accepted?.label, DashHead.materialUnpaved)
        XCTAssertGreaterThanOrEqual(accepted?.confidence ?? 0, DriveRules.cameraConfidence)

        var split = DashConsensus()
        for index in 0..<6 {
            accepted = split.observe(index.isMultiple(of: 2) ? unpaved : paved)
        }
        XCTAssertNil(accepted)

        var weak = DashConsensus()
        let shy: [Float] = [0.2, 0.7, 0.1]
        for index in 0..<6 {
            accepted = weak.observe(index < 4 ? shy : paved)
        }
        XCTAssertNil(accepted)
    }

    func testDryWetAndSmoothChangeNothingAndWaterOrSevereOnlyMoveEarlier() {
        let dry = DashVote(label: DashHead.frictionDry, confidence: 0.9)
        let wet = DashVote(label: DashHead.frictionWet, confidence: 0.9)
        let smooth = DashVote(label: DashHead.unevenSmooth, confidence: 0.9)
        XCTAssertEqual(visionCaution(material: nil, friction: dry, uneven: smooth, fileSurface: .paved), .quiet)
        XCTAssertEqual(visionCaution(material: nil, friction: wet, uneven: nil, fileSurface: .paved), .quiet)

        let water = visionCaution(
            material: nil,
            friction: DashVote(label: DashHead.frictionWater, confidence: 0.9),
            uneven: nil,
            fileSurface: .paved
        )
        XCTAssertTrue(water.standingWaterOrSnow)
        XCTAssertFalse(water.severeUnevenOnPaved)
        let snow = visionCaution(
            material: nil,
            friction: DashVote(label: DashHead.frictionSnowIce, confidence: 0.9),
            uneven: nil,
            fileSurface: .unpaved
        )
        XCTAssertTrue(snow.standingWaterOrSnow)

        let severe = DashVote(label: DashHead.unevenSevere, confidence: 0.91)
        XCTAssertTrue(visionCaution(material: nil, friction: nil, uneven: severe, fileSurface: .paved).severeUnevenOnPaved)
        XCTAssertFalse(visionCaution(material: nil, friction: nil, uneven: severe, fileSurface: .unpaved).severeUnevenOnPaved)
        let lowered = DashVote(label: DashHead.materialUnpaved, confidence: 0.9)
        XCTAssertFalse(visionCaution(material: lowered, friction: nil, uneven: severe, fileSurface: .paved).severeUnevenOnPaved)

        let base = baseLookAheadMeters(speedMps: 15)
        let earlier = lookAheadMeters(speedMps: 15, memory: ApproachMemory(latePasses: 0, earlyPasses: 0), vision: water)
        XCTAssertGreaterThan(earlier, base)
        XCTAssertEqual(
            lookAheadMeters(speedMps: 15, memory: ApproachMemory(latePasses: 0, earlyPasses: 0), vision: .quiet),
            base,
            accuracy: 0.01
        )
    }

    func testMaterialEvidenceCanOnlyLowerThroughTheExistingFuse() {
        let reading = dashReading(
            material: DashVote(label: DashHead.materialUnpaved, confidence: 0.92),
            friction: nil,
            uneven: nil,
            fileSurface: .paved,
            state: .running,
            acceptedAt: Date()
        )
        let fused = fuseSurface(fileLabel: .paved, camera: reading.camera, threshold: DriveRules.cameraConfidence)
        XCTAssertEqual(fused.0, .unpaved)
        XCTAssertEqual(fused.1, .cameraLowered)
        let conflict = fuseSurface(fileLabel: .unpaved, camera: reading.camera, threshold: DriveRules.cameraConfidence)
        XCTAssertEqual(conflict.0, .unpaved)
    }

    func testRoadCropIsTheLowerCenter() {
        let crop = DashCrop.road(in: CGRect(x: 0, y: 0, width: 100, height: 200))
        XCTAssertEqual(crop, CGRect(x: 25, y: 0, width: 50, height: 90))
    }

    func testClockKeepsAboutFiveFramesPerSecond() {
        var clock = DashClock()
        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(clock.allow(start))
        XCTAssertFalse(clock.allow(start.addingTimeInterval(0.1)))
        XCTAssertTrue(clock.allow(start.addingTimeInterval(0.2)))
    }

    func testAStaleCameraFallsBackToTheCountyFile() throws {
        let engine = try makeEngine()
        let moment = date(hour: 14)
        try engine.beginTrip(driverMode: .adult, at: moment, startSensors: false)
        engine.dashEnabled = true
        let camera = CameraEvidence(label: .unpaved, confidence: 0.95, age: 0, onMatchedRoadROI: true, persistent: true)
        engine.updateVision(.quiet, camera: camera, acceptedAt: moment.addingTimeInterval(-2))
        let stale = engine.handle(fix: fix(speed: 20, at: moment), nearby: [line(id: "c", north: 80)], now: moment)
        XCTAssertEqual(stale.surface, .paved)
        XCTAssertEqual(stale.surfaceUI, .unconfirmed)
        engine.updateVision(.quiet, camera: camera, acceptedAt: moment)
        let fresh = engine.handle(fix: fix(speed: 20, at: moment.addingTimeInterval(1)), nearby: [line(id: "c", north: 80)], now: moment.addingTimeInterval(1))
        XCTAssertEqual(fresh.surface, .unpaved)
        XCTAssertEqual(fresh.surfaceUI, .cameraLowered)
        let water = VisionCaution(standingWaterOrSnow: true, severeUnevenOnPaved: false)
        engine.updateVision(water, camera: camera, acceptedAt: moment.addingTimeInterval(1))
        let earlier = engine.handle(fix: fix(speed: 20, at: moment.addingTimeInterval(2)), nearby: [line(id: "c", north: 80)], now: moment.addingTimeInterval(2))
        XCTAssertGreaterThan(earlier.lookAheadMeters ?? 0, baseLookAheadMeters(speedMps: 20))
        engine.updateVision(.quiet, camera: nil)
        let cooled = engine.handle(fix: fix(speed: 20, at: moment.addingTimeInterval(3)), nearby: [line(id: "c", north: 80)], now: moment.addingTimeInterval(3))
        XCTAssertEqual(cooled.surface, .paved)
        XCTAssertEqual(cooled.lookAheadMeters ?? -1, baseLookAheadMeters(speedMps: 20), accuracy: 0.01)
    }

    func testDashStartsOnlyWhenTheGateAllowsTheCamera() throws {
        DashPreference.isOn = true
        let underage = SpyDash()
        let underHarness = try makeSession(camera: underage)
        underHarness.bridge.start(mode: .under18, style: .normal, uploadOptIn: true)
        XCTAssertEqual(underage.starts, 0)
        XCTAssertEqual(underHarness.bridge.drive.cameraStatus, "Surface unconfirmed")
        XCTAssertFalse(driveGate(mode: .under18, speedMps: 12, dashEnabled: true, uploadOptIn: false).allowsCamera)

        DashPreference.isOn = true
        let adult = SpyDash()
        let adultHarness = try makeSession(camera: adult)
        adultHarness.bridge.start(mode: .adult, style: .normal, uploadOptIn: false)
        XCTAssertEqual(adult.starts, 1)
        XCTAssertTrue(adultHarness.engine.dashEnabled)
        XCTAssertEqual(adultHarness.bridge.drive.tripTitle, "Dash")
        adult.onChange?(DashReading(
            camera: CameraEvidence(label: .unpaved, confidence: 0.9, age: 0, onMatchedRoadROI: true, persistent: true),
            vision: VisionCaution(standingWaterOrSnow: true, severeUnevenOnPaved: false),
            state: .running,
            acceptedAt: Date()
        ))
        XCTAssertEqual(adultHarness.bridge.drive.cameraStatus, "Dash · camera on")
        XCTAssertEqual(adultHarness.bridge.drive.cameraEvidence?.label, .unpaved)
        XCTAssertEqual(adultHarness.bridge.drive.cameraThreshold, DriveRules.cameraConfidence)

        DashPreference.isOn = false
        let copilot = SpyDash()
        let copilotHarness = try makeSession(camera: copilot)
        copilotHarness.bridge.start(mode: .passenger, style: .short, uploadOptIn: false)
        XCTAssertEqual(copilot.starts, 0)
        XCTAssertEqual(copilotHarness.bridge.drive.cameraStatus, "Off · Co-pilot mode")
        XCTAssertNil(copilotHarness.bridge.drive.cameraEvidence)
    }

    func testAMissingPackageOrSeriousHeatDoesNotLoadTheModel() {
        let missing = DashCamera(loader: { throw DashModelError.missingPackage }, thermal: { false })
        XCTAssertFalse(missing.didLoadModel)
        let missingExpectation = expectation(description: "missing model")
        missing.onChange = { reading in
            if reading.state == .unconfirmed && reading.camera == nil {
                missingExpectation.fulfill()
            }
        }
        missing.start()

        let hot = DashCamera(loader: { throw DashModelError.unreadable }, thermal: { true })
        let hotExpectation = expectation(description: "thermal stop")
        hot.onChange = { reading in
            if reading.state == .unconfirmed && reading.vision == .quiet {
                hotExpectation.fulfill()
            }
        }
        hot.start()
        wait(for: [missingExpectation, hotExpectation], timeout: 2)
        XCTAssertFalse(missing.didLoadModel)
        XCTAssertFalse(hot.didLoadModel)
    }

    func testBundledModelOutputsAreMaterialFrictionAndUneven() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "RoadSurface", withExtension: "mlmodelc"))
        let model = try MLModel(contentsOf: url)
        XCTAssertEqual(Set(model.modelDescription.outputDescriptionsByName.keys), ["material", "friction", "uneven"])
    }

    private func makeEngine() throws -> TripEngine {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dash-\(UUID().uuidString).sqlite")
        let log = try PassLog(databaseURL: url)
        return TripEngine(store: IdleCurves(), passLog: log, speech: IdleSpeech())
    }

    private func makeSession(camera: SpyDash) throws -> (bridge: TripScreenBridge, engine: TripEngine) {
        let engine = try makeEngine()
        let bridge = TripScreenBridge()
        let session = LiveTripSession(
            engine: engine,
            bridge: bridge,
            curves: try SQLiteCurveStore.openBundled(),
            startSensors: false,
            camera: camera
        )
        sessions.append(session)
        return (bridge, engine)
    }

    private func line(id: String, north: Double) -> Curve {
        let latitude = 36.0 + north / Geo.metersPerDegreeLatitude
        let point = MapPoint(longitude: -94, latitude: latitude)
        return Curve(
            id: id, county: "Benton", roadName: "Test Rd", surface: .paved, radiusFeet: 200,
            deflectionDegrees: 20, qualityFlags: "", roadClass: "County", roadDesign: "Single Carriageway",
            closedLoop: false, latitude: point.latitude, longitude: point.longitude,
            minLatitude: point.latitude, maxLatitude: point.latitude + 0.001,
            minLongitude: point.longitude, maxLongitude: point.longitude,
            coordinates: [point, MapPoint(longitude: -94, latitude: point.latitude + 40 / Geo.metersPerDegreeLatitude)]
        )
    }

    private func fix(speed: Double, at moment: Date) -> LocationFix {
        LocationFix(
            latitude: 36, longitude: -94, speedMps: speed, speedAccuracyMps: 0.5,
            courseDegrees: 0, horizontalAccuracyMeters: 5, timestamp: moment
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

private final class SpyDash: DashRunning {
    var starts = 0
    var stops = 0
    var pauses = 0
    var onChange: ((DashReading) -> Void)?
    func start() { starts += 1 }
    func stop() { stops += 1 }
    func pause() { pauses += 1 }
    func noteMatchedSurface(_ surface: RoadSurface?) {}
}

private final class IdleCurves: CurveStore {
    func curves(nearLatitude latitude: Double, longitude: Double, radiusMeters: Double) -> [Curve] { [] }
}

private final class IdleSpeech: PromptPlaying {
    func speakWarning() throws {}
    func playChime() throws {}
}
