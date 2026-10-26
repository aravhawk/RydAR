import XCTest
@testable import RydAR

final class CurveDataMigrationTests: XCTestCase {
    private func scratchDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func pass(_ curveID: String) -> CompletedPass {
        CompletedPass(
            curveID: curveID, direction: "N", effectiveSpeedMPH: 40, vLoMPH: 20, vHiMPH: 25,
            spoke: true, hourBucket: 10, late: true, surfaceUsed: .unpaved, radiusBand: "under-150",
            lookAheadMeters: 150, contextKey: "unpaved|under-150|day", brakingDistanceMeters: 90
        )
    }

    func testTheBundledRoadFileOpensInPlaceAndHoldsCurves() throws {
        let store = try SQLiteCurveStore.openBundled()
        XCTAssertFalse(store.counties().isEmpty)
    }

    func testTripsMoveOutOfACombinedFileAndTheOldFileIsRemoved() throws {
        let directory = try scratchDirectory()
        let legacy = directory.appendingPathComponent("curves.sqlite")
        let target = directory.appendingPathComponent("passlog.sqlite")
        var tripID = ""
        do {
            let log = try PassLog(databaseURL: legacy)
            tripID = try log.startTrip(mode: .adult)
            try log.record(pass("001-1-1"), tripID: tripID)
        }

        XCTAssertTrue(try BundledCurves.migrateLegacy(from: legacy, to: target))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))

        let moved = try PassLog(databaseURL: target)
        XCTAssertEqual(try moved.passes(forTrip: tripID).count, 1)
        XCTAssertEqual(try moved.passes(forTrip: tripID).first?.pass.brakingDistanceMeters, 90)
        XCTAssertEqual(try moved.memory(for: "unpaved|under-150|day").latePasses, 1)
        XCTAssertEqual(try moved.curveMemory(for: "001-1-1").latePasses, 1)
    }

    func testRunningTheMoveTwiceDoesNotDoubleCountOrFail() throws {
        let directory = try scratchDirectory()
        let legacy = directory.appendingPathComponent("curves.sqlite")
        let target = directory.appendingPathComponent("passlog.sqlite")
        var tripID = ""
        do {
            let log = try PassLog(databaseURL: legacy)
            tripID = try log.startTrip(mode: .adult)
            try log.record(pass("001-1-1"), tripID: tripID)
        }
        XCTAssertTrue(try BundledCurves.migrateLegacy(from: legacy, to: target))
        XCTAssertFalse(try BundledCurves.migrateLegacy(from: legacy, to: target))
        XCTAssertEqual(try PassLog(databaseURL: target).passes(forTrip: tripID).count, 1)
    }

    func testAFreshInstallHasNothingToMove() throws {
        let directory = try scratchDirectory()
        XCTAssertFalse(try BundledCurves.migrateLegacy(
            from: directory.appendingPathComponent("curves.sqlite"),
            to: directory.appendingPathComponent("passlog.sqlite")))
    }
}
