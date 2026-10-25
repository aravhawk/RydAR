import XCTest
@testable import CurveAudit

final class SQLiteCurveStoreTests: XCTestCase {
    func testNearbyQueryUsesTheBoundingBoxColumns() {
        let sql = SQLiteCurveStore.nearbySQL.lowercased()
        XCTAssertTrue(sql.contains("min_lat"))
        XCTAssertTrue(sql.contains("max_lat"))
        XCTAssertTrue(sql.contains("min_lon"))
        XCTAssertTrue(sql.contains("max_lon"))
        XCTAssertTrue(sql.contains("where"))
        XCTAssertFalse(sql.contains("select *"))
    }

    func testRadiusLookupDoesNotReturnDistantCurves() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("curves-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
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
        try insert(
            writer,
            id: "local",
            latitude: 36,
            longitude: -94,
            minLatitude: 35.999,
            maxLatitude: 36.001,
            minLongitude: -94.001,
            maxLongitude: -93.999,
            coordinates: [[-94, 36], [-94, 36.0001]],
            roadDesign: "Single Carriageway"
        )
        try insert(
            writer,
            id: "far",
            latitude: 10,
            longitude: 10,
            minLatitude: 9.9,
            maxLatitude: 10.1,
            minLongitude: 9.9,
            maxLongitude: 10.1,
            coordinates: [[10, 10], [10.001, 10]],
            roadDesign: "Single Carriageway"
        )
        try insert(
            writer,
            id: "decoy-bbox",
            latitude: 10,
            longitude: 10,
            minLatitude: -90,
            maxLatitude: 90,
            minLongitude: -180,
            maxLongitude: 180,
            coordinates: [[10, 10], [10.001, 10]],
            roadDesign: "At-Grade Ramp"
        )

        let store = try SQLiteCurveStore(databaseURL: url)
        XCTAssertTrue(store.curves(nearLatitude: 36, longitude: -94, radiusMeters: 0).isEmpty)
        let near = store.curves(nearLatitude: 36, longitude: -94, radiusMeters: 1_000)
        XCTAssertEqual(near.map(\.id), ["local"])
        XCTAssertEqual(near.first?.roadDesign, "Single Carriageway")
        XCTAssertEqual(near.first?.surface, .paved)
        XCTAssertEqual(near.first?.coordinates.count, 2)
    }

    func testBundledDatabaseReturnsANeighborhoodNotEveryCurve() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("ios/CurveAudit/curves.sqlite")
        let store = try SQLiteCurveStore(databaseURL: url)
        let near = store.curves(nearLatitude: 36.394111, longitude: -94.119669, radiusMeters: 500)
        XCTAssertGreaterThan(near.count, 0)
        XCTAssertLessThan(near.count, 250)
        for curve in near {
            let distance = Geo.distanceToCurve(latitude: 36.394111, longitude: -94.119669, curve: curve)
            XCTAssertLessThanOrEqual(distance, 500)
        }
        XCTAssertTrue(store.curves(nearLatitude: 0, longitude: 0, radiusMeters: 1_000).isEmpty)
    }

    private func insert(
        _ connection: SQLiteConnection,
        id: String,
        latitude: Double,
        longitude: Double,
        minLatitude: Double,
        maxLatitude: Double,
        minLongitude: Double,
        maxLongitude: Double,
        coordinates: [[Double]],
        roadDesign: String
    ) throws {
        let data = try JSONSerialization.data(withJSONObject: coordinates)
        let json = String(decoding: data, as: UTF8.self)
        try connection.run(
            """
            INSERT INTO curves (
              id, county, road_name, surface, radius_ft, deflection_deg, rd_class, rd_design,
              closed_loop, quality_flags, lat, lon, min_lat, max_lat, min_lon, max_lon, coordinates_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        ) { statement in
            connection.bind(statement, 1, id)
            connection.bind(statement, 2, "Benton")
            connection.bind(statement, 3, "Test Rd")
            connection.bind(statement, 4, "paved")
            connection.bind(statement, 5, 200.0)
            connection.bind(statement, 6, 40.0)
            connection.bind(statement, 7, "County")
            connection.bind(statement, 8, roadDesign)
            connection.bind(statement, 9, 0)
            connection.bind(statement, 10, "")
            connection.bind(statement, 11, latitude)
            connection.bind(statement, 12, longitude)
            connection.bind(statement, 13, minLatitude)
            connection.bind(statement, 14, maxLatitude)
            connection.bind(statement, 15, minLongitude)
            connection.bind(statement, 16, maxLongitude)
            connection.bind(statement, 17, json)
        }
    }
}
