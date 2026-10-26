import MapKit
import XCTest
@testable import RydAR

final class SQLiteCurveStoreTests: XCTestCase {
    func testNearbyQueryUsesTheBoundingBoxColumns() {
        let sql = SQLiteCurveStore.nearbySQL.lowercased()
        XCTAssertTrue(sql.contains("min_lat"))
        XCTAssertTrue(sql.contains("max_lat"))
        XCTAssertTrue(sql.contains("min_lon"))
        XCTAssertTrue(sql.contains("max_lon"))
        XCTAssertTrue(sql.contains("where"))
        XCTAssertFalse(sql.contains("select *"))
        let byID = SQLiteCurveStore.curveByIDSQL.lowercased()
        XCTAssertTrue(byID.contains("where id = ?"))
        XCTAssertFalse(byID.contains("select *"))
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
            .appendingPathComponent("ios/RydAR/curves.sqlite")
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

    func testSearchFindsAPartialRoadNameAndSkipsGeometry() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("curves-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try SQLiteConnection(url: url, readonly: false)
        try writer.execute(Self.curveTable)
        try insert(
            writer, id: "wire", latitude: 36.26, longitude: -94.12,
            minLatitude: 36.26, maxLatitude: 36.27, minLongitude: -94.13, maxLongitude: -94.11,
            coordinates: [[-94.12, 36.26], [-94.11, 36.27]],
            roadDesign: "Single Carriageway", roadName: "N Old Wire Rd")
        try insert(
            writer, id: "south", latitude: 36.10, longitude: -94.10,
            minLatitude: 36.10, maxLatitude: 36.11, minLongitude: -94.11, maxLongitude: -94.09,
            coordinates: [[-94.10, 36.10], [-94.09, 36.11]],
            roadDesign: "Single Carriageway", roadName: "S Wire Rd")
        try insert(
            writer, id: "other", latitude: 36.32, longitude: -93.99,
            minLatitude: 36.32, maxLatitude: 36.33, minLongitude: -94.00, maxLongitude: -93.98,
            coordinates: [[-93.99, 36.32], [-93.98, 36.33]],
            roadDesign: "Single Carriageway", roadName: "Canyon Village Rd")
        try insert(
            writer, id: "secret", latitude: 36.20, longitude: -94.00,
            minLatitude: 36.20, maxLatitude: 36.21, minLongitude: -94.01, maxLongitude: -93.99,
            coordinates: [[-94.00, 36.20], [-93.99, 36.21]],
            roadDesign: "Single Carriageway", roadName: "Secret Lane", roadClass: "Private")

        let store = try SQLiteCurveStore(databaseURL: url)
        XCTAssertTrue(store.searchRoads("w", limit: 8).isEmpty)
        let before = store.searchRoads("wire", limit: 8)
        XCTAssertEqual(Set(before.map(\.id)), ["wire", "south"])
        XCTAssertTrue(before.allSatisfy { $0.coordinates.isEmpty })
        XCTAssertTrue(store.searchRoads("secret", limit: 4).isEmpty)
        store.warmSearchIndex()
        let after = store.searchRoads("wire", limit: 8)
        XCTAssertEqual(after.map(\.roadName), ["N Old Wire Rd", "S Wire Rd"])
        XCTAssertEqual(after.map(\.id), ["wire", "south"])
        XCTAssertTrue(after.allSatisfy { $0.coordinates.isEmpty })
        XCTAssertEqual(store.curve(id: "wire")?.coordinates.count, 2)
        XCTAssertTrue(store.searchRoads("secret", limit: 4).isEmpty)
        XCTAssertTrue(store.searchRoads("village", limit: 4).map(\.id) == ["other"])
    }

    func testMapFramingRejectsAContinentSpanAndANullIslandCurve() {
        let road = MapFraming.cameraDistance(
            latitudeDelta: 0.02, longitudeDelta: 0.02, latitude: 35,
            clamp: 2_000...12_000)
        XCTAssertGreaterThan(road, 3_000)
        XCTAssertLessThan(road, 6_000)
        let continent = MapFraming.cameraDistance(
            latitudeDelta: 40, longitudeDelta: 60, latitude: 40,
            clamp: MapFraming.minimumDistance...MapFraming.maximumDistance)
        XCTAssertEqual(continent, MapFraming.maximumDistance)
        XCTAssertEqual(MapFraming.roadCameraDistance, 4_200)
        XCTAssertLessThan(MapFraming.roadCameraDistance, MapFraming.maximumDistance)
        XCTAssertFalse(MapFraming.usable(latitude: 0, longitude: 0))
        XCTAssertFalse(MapFraming.usable(latitude: -94, longitude: 36))
        XCTAssertTrue(MapFraming.usable(latitude: 36.27, longitude: -94.12))
        var missing = PreviewCurves.samples[0]
        missing.latitude = 0
        missing.longitude = 0
        missing.minLatitude = 0
        missing.maxLatitude = 0
        missing.minLongitude = 0
        missing.maxLongitude = 0
        XCTAssertNil(MapFraming.focusCoordinate(missing))
        let focus = MapFraming.focusCoordinate(PreviewCurves.samples[0])
        XCTAssertEqual(focus?.latitude ?? 0, PreviewCurves.samples[0].latitude, accuracy: 0.000_001)
        XCTAssertEqual(focus?.longitude ?? 0, PreviewCurves.samples[0].longitude, accuracy: 0.000_001)
        let state = MapFraming.cameraDistance(
            latitudeDelta: 4.2, longitudeDelta: 4.2, latitude: 34.8,
            clamp: MapFraming.minimumDistance...MapFraming.maximumDistance)
        XCTAssertGreaterThan(state, 500_000)
        XCTAssertLessThan(state, MapFraming.maximumDistance)
    }

    private static let curveTable = """
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
        roadDesign: String,
        roadName: String = "Test Rd",
        roadClass: String = "County"
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
            connection.bind(statement, 3, roadName)
            connection.bind(statement, 4, "paved")
            connection.bind(statement, 5, 200.0)
            connection.bind(statement, 6, 40.0)
            connection.bind(statement, 7, roadClass)
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
