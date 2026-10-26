import XCTest
@testable import RydAR

final class PassLogTests: XCTestCase {
    func testLatePassRules() {
        XCTAssertFalse(passWasLate(brakingOnsetDistanceMeters: nil, baseLookAheadMeters: 140, fastAboveRangeInsideFortyMeters: false))
        XCTAssertTrue(passWasLate(brakingOnsetDistanceMeters: nil, baseLookAheadMeters: 140, fastAboveRangeInsideFortyMeters: true))
        XCTAssertTrue(passWasLate(brakingOnsetDistanceMeters: 100, baseLookAheadMeters: 140, fastAboveRangeInsideFortyMeters: false))
        XCTAssertFalse(passWasLate(brakingOnsetDistanceMeters: 140, baseLookAheadMeters: 140, fastAboveRangeInsideFortyMeters: false))
        XCTAssertFalse(passWasLate(brakingOnsetDistanceMeters: 200, baseLookAheadMeters: 140, fastAboveRangeInsideFortyMeters: false))
        XCTAssertTrue(passWasLate(brakingOnsetDistanceMeters: 200, baseLookAheadMeters: 140, fastAboveRangeInsideFortyMeters: true))
    }

    func testBrakingDistanceRoundTrips() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brake-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let log = try PassLog(databaseURL: url)
        let tripID = try log.startTrip(mode: .passenger)
        var pass = CompletedPass(
            curveID: "007-2-3",
            direction: "N",
            effectiveSpeedMPH: 30,
            vLoMPH: 19,
            vHiMPH: 23,
            spoke: true,
            hourBucket: 14,
            late: true,
            surfaceUsed: .paved,
            radiusBand: "150-300",
            lookAheadMeters: 140,
            contextKey: "paved|150-300|day",
            brakingDistanceMeters: 80
        )
        try log.record(pass, tripID: tripID)
        pass.brakingDistanceMeters = nil
        pass.curveID = "143-1-1"
        try log.record(pass, tripID: tripID)
        let rows = try log.passes(forTrip: tripID)
        XCTAssertEqual(rows[0].pass.brakingDistanceMeters, 80)
        XCTAssertNil(rows[1].pass.brakingDistanceMeters)
    }

    func testOneLatePassDoesNotMarkTheContext() {
        XCTAssertFalse(contextSaysLate(ApproachMemory(latePasses: 1, earlyPasses: 0)))
        XCTAssertTrue(contextSaysLate(ApproachMemory(latePasses: 3, earlyPasses: 0)))
    }

    func testTripsPassesAndMemoryUseTheContractTables() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("passes-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let log = try PassLog(databaseURL: url)
        let side = try SQLiteConnection(url: url, readonly: false)
        try side.execute("CREATE TABLE IF NOT EXISTS curves (id TEXT PRIMARY KEY);")
        try side.run("INSERT INTO curves (id) VALUES (?)", bind: { statement in
            side.bind(statement, 1, "keep-me")
        })

        let when = Date(timeIntervalSince1970: 1_700_000_000)
        let tripID = try log.startTrip(mode: .adult, at: when, notes: "parked preview")
        let trip = try XCTUnwrap(log.trip(id: tripID))
        XCTAssertEqual(trip.driverMode, .adult)
        XCTAssertEqual(trip.notes, "parked preview")
        XCTAssertFalse(trip.startedAt.isEmpty)

        let under = try log.startTrip(mode: .under18, at: when)
        XCTAssertEqual(try log.trip(id: under)?.driverMode, .under18)

        let nightKey = approachContextKey(surface: .unpaved, radiusFeet: 120, hour: 21)
        XCTAssertEqual(nightKey, "unpaved|under-150|night")
        try log.record(sample(curveID: "a", speed: 40, low: 15, late: true, key: nightKey, band: "under-150", hour: 21, surface: .unpaved), tripID: tripID)
        try log.record(sample(curveID: "b", speed: 10, low: 20, late: false, key: nightKey, band: "under-150", hour: 21, surface: .unpaved), tripID: tripID)

        let memory = try log.memory(for: nightKey)
        XCTAssertEqual(memory.latePasses, 1)
        XCTAssertEqual(memory.earlyPasses, 1)
        XCTAssertEqual(try log.passesUnderRange(curveID: "b"), 1)
        XCTAssertEqual(try log.passesUnderRange(curveID: "a"), 0)

        let stored = try log.passes(forTrip: tripID)
        XCTAssertEqual(stored.map(\.pass.curveID), ["a", "b"])
        XCTAssertEqual(stored[0].pass.contextKey, nightKey)
        XCTAssertTrue(stored[0].pass.late)
        XCTAssertFalse(stored[1].pass.late)
        XCTAssertNil(stored[0].pass.brakingDistanceMeters)

        let dayKey = approachContextKey(surface: .paved, radiusFeet: 200, hour: 14)
        try log.record(sample(curveID: "wide", speed: 50, low: 20, late: true, key: dayKey, band: "150-300", hour: 14, surface: .paved), tripID: tripID)
        try log.record(sample(curveID: "tight", speed: 30, low: 15, late: true, key: dayKey, band: "150-300", hour: 14, surface: .paved), tripID: tripID)
        try log.record(sample(curveID: "again", speed: 28, low: 15, late: true, key: dayKey, band: "150-300", hour: 14, surface: .paved), tripID: tripID)
        let over = try log.overRangePasses(forTrip: tripID)
        XCTAssertEqual(over.map(\.pass.curveID), ["wide", "a", "tight", "again"])
        XCTAssertEqual(try log.lateContexts().map(\.key), [dayKey])

        try log.deleteAll()
        XCTAssertTrue(try log.passes(forTrip: tripID).isEmpty)
        XCTAssertEqual(try log.memory(for: dayKey).latePasses, 0)
        var kept = 0
        try side.query("SELECT COUNT(*) FROM curves", { statement in
            kept = side.int(statement, 0)
        })
        XCTAssertEqual(kept, 1)
    }

    func testBrakingDistancePlacesTheNextWarningAndThenClears() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("onset-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let log = try PassLog(databaseURL: url)
        let tripID = try log.startTrip(mode: .passenger)
        let key = approachContextKey(surface: .unpaved, radiusFeet: 120, hour: 21)
        for _ in 0..<3 {
            var pass = sample(curveID: "same", speed: 30, low: 15, late: true, key: key, band: "under-150", hour: 21, surface: .unpaved)
            pass.brakingDistanceMeters = 40
            try log.record(pass, tripID: tripID)
        }
        var quiet = sample(curveID: "same", speed: 10, low: 20, late: false, key: key, band: "under-150", hour: 21, surface: .unpaved)
        quiet.brakingDistanceMeters = nil
        try log.record(quiet, tripID: tripID)
        let onset = try log.onset(forCurve: "same")
        XCTAssertEqual(onset.count, 3)
        XCTAssertEqual(onset.sumMeters, 120, accuracy: 0.001)
        XCTAssertEqual(try log.onset(forContext: key).count, 3)
        XCTAssertEqual(try log.curvesWithEarlierPrompt(), 1)
        try log.deleteAll()
        XCTAssertEqual(try log.onset(forCurve: "same").count, 0)
        XCTAssertEqual(try log.curvesWithEarlierPrompt(), 0)
    }

    private func sample(
        curveID: String,
        speed: Double,
        low: Double,
        late: Bool,
        key: String,
        band: String,
        hour: Int,
        surface: RoadSurface
    ) -> CompletedPass {
        CompletedPass(
            curveID: curveID,
            direction: "N",
            effectiveSpeedMPH: speed,
            vLoMPH: low,
            vHiMPH: low + 3,
            spoke: late,
            hourBucket: hour,
            late: late,
            surfaceUsed: surface,
            radiusBand: band,
            lookAheadMeters: 140,
            contextKey: key
        )
    }
}
