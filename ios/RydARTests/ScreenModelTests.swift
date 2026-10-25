import XCTest
@testable import RydAR

final class ScreenModelTests: XCTestCase {
    private let curve = PreviewCurves.samples[0]

    private func pass(_ id: String, speed: Double, low: Double = 10, high: Double = 14) -> TripCurvePass {
        TripCurvePass(id: id, curve: curve, effectiveMPH: speed,
                      range: ScreeningRange(low: low, high: high), surfaceUsed: .unpaved)
    }

    func testDebriefUsesRecordedLowEndAndSortsLargestGapFirst() {
        let debrief = TripScreenDebrief(passes: [pass("inside", speed: 12), pass("at-low", speed: 10),
                                               pass("largest", speed: 24), pass("camera-lowered", speed: 9, low: 5)])
        XCTAssertEqual(debrief.overRangePasses.map(\.id), ["largest", "camera-lowered", "inside"])
        XCTAssertEqual(debrief.overRangePasses.first?.gapAboveLowEnd, 14)
    }

    func testDebriefContextsFollowSharedTimingPolicy() {
        let one = TimingContextSummary(surface: .unpaved, representativeRadiusFeet: 114.5,
                                       hour: 21, memory: ApproachMemory(latePasses: 1, earlyPasses: 0))
        let late = TimingContextSummary(surface: .unpaved, representativeRadiusFeet: 114.5,
                                        hour: 21, memory: ApproachMemory(latePasses: 3, earlyPasses: 0))
        XCTAssertFalse(one.movesPromptEarlier)
        XCTAssertTrue(late.movesPromptEarlier)
        XCTAssertEqual(late.message, "On tight unpaved roads you brake late. The next prompt in that situation comes earlier.")
        XCTAssertEqual(TripScreenDebrief(contexts: [one, late]).lateContexts.count, 1)
    }

    func testNewTripClearsPreviousRowsAndUnder18CannotOptInWhileMoving() async {
        await MainActor.run {
            let trip = TripScreenBridge()
            XCTAssertNil(trip.driverMode)
            var uploads: [Bool] = []
            trip.onStart = { _, _, upload in uploads.append(upload) }
            trip.debrief = TripScreenDebrief(passes: [self.pass("old-trip", speed: 20)])
            trip.drive.distanceMeters = 100
            trip.start(mode: .under18, style: .normal, uploadOptIn: true)
            XCTAssertEqual(uploads, [false])
            XCTAssertTrue(trip.debrief.passes.isEmpty)
            XCTAssertNil(trip.drive.distanceMeters)
            trip.start(mode: .passenger, style: .short, uploadOptIn: true)
            XCTAssertEqual(uploads, [false, true])
        }
    }

    func testConnectedStoreCannotPretendDeletionWorkedWithoutAnAction() async throws {
        try await MainActor.run {
            let trip = TripScreenBridge()
            trip.onStart = { _, _, _ in }
            trip.onPause = { _ in }
            trip.onFinish = {}
            trip.debrief = TripScreenDebrief(passes: [self.pass("saved", speed: 20)])
            XCTAssertTrue(trip.isConnected)
            XCTAssertThrowsError(try trip.deleteAllData())
            XCTAssertEqual(trip.debrief.passes.count, 1)
            var deleted = false
            trip.onDeleteAllData = { deleted = true }
            XCTAssertNoThrow(try trip.deleteAllData())
            XCTAssertTrue(deleted)
            XCTAssertTrue(trip.debrief.passes.isEmpty)
        }
    }

    func testExportIncludesOnlyThisTripsRowsAndEscapesCells() {
        var sample = pass("own-pass", speed: 15)
        sample.curve.roadName = "=SUM(1,2)\"Lane"
        let csv = LocalTripExport.csv(TripScreenDebrief(tripID: "this-trip", passes: [sample]))
        XCTAssertTrue(csv.contains("\"this-trip\",\"007-2-3\""))
        XCTAssertTrue(csv.contains("\"'=SUM(1,2)\"\"Lane\""))
        XCTAssertFalse(csv.contains("latitude"))
        XCTAssertFalse(csv.contains("longitude"))
        XCTAssertEqual(csv.split(separator: "\n").count, 2)
    }

    func testFiveCurveStoreHonorsAreaAndContainsReplayTarget() {
        XCTAssertEqual(PreviewCurves.samples.count, 5)
        let store = PreviewCurves()
        let nearby = store.curves(nearLatitude: curve.latitude, longitude: curve.longitude, radiusMeters: 50)
        XCTAssertTrue(nearby.contains { $0.id == "007-2-3" })
        XCTAssertTrue(store.curves(nearLatitude: 0, longitude: 0, radiusMeters: 50).isEmpty)
    }
}
