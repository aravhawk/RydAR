import Foundation
import SQLite3

enum CurveDatabaseError: Error {
    case missingBundle
    case openFailed(String)
    case statementFailed(String)
}

/// The bundled curve file is read-only. Trip rows live in an Application Support copy.
enum BundledCurves {
    static func bundleURL() -> URL? {
        Bundle.main.url(forResource: "curves", withExtension: "sqlite")
    }

    static func supportURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("RydAR", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("curves.sqlite")
    }

    /// Copies the bundle once. Does not query the curves table.
    static func prepareWritableCopy() throws -> URL {
        let destination = try supportURL()
        if FileManager.default.fileExists(atPath: destination.path) {
            return destination
        }
        guard let bundled = bundleURL() else {
            throw CurveDatabaseError.missingBundle
        }
        try FileManager.default.copyItem(at: bundled, to: destination)
        return destination
    }
}

final class SQLiteConnection {
    static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    let db: OpaquePointer

    init(url: URL, readonly: Bool) throws {
        var handle: OpaquePointer?
        let flags: Int32 = readonly
            ? SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
            : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let code = sqlite3_open_v2(url.path, &handle, flags, nil)
        guard code == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unable to open \(url.path)"
            if let handle {
                sqlite3_close(handle)
            }
            throw CurveDatabaseError.openFailed(message)
        }
        db = handle
        sqlite3_busy_timeout(db, 3_000)
    }

    deinit {
        sqlite3_close(db)
    }

    func execute(_ sql: String) throws {
        var message: UnsafeMutablePointer<CChar>?
        let code = sqlite3_exec(db, sql, nil, nil, &message)
        guard code == SQLITE_OK else {
            let text = message.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(db))
            sqlite3_free(message)
            throw CurveDatabaseError.statementFailed(text)
        }
    }

    func run(_ sql: String, bind: (OpaquePointer) -> Void = { _ in }) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bind(statement)
        let code = sqlite3_step(statement)
        guard code == SQLITE_DONE else {
            throw CurveDatabaseError.statementFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    func query(
        _ sql: String,
        _ row: (OpaquePointer) throws -> Void,
        bind: (OpaquePointer) -> Void = { _ in }
    ) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bind(statement)
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_ROW {
                try row(statement)
            } else if code == SQLITE_DONE {
                return
            } else {
                throw CurveDatabaseError.statementFailed(String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    func isNull(_ statement: OpaquePointer, _ index: Int32) -> Bool {
        sqlite3_column_type(statement, index) == SQLITE_NULL
    }

    func text(_ statement: OpaquePointer, _ index: Int32) -> String {
        guard let raw = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: raw)
    }

    func double(_ statement: OpaquePointer, _ index: Int32) -> Double {
        sqlite3_column_double(statement, index)
    }

    func int(_ statement: OpaquePointer, _ index: Int32) -> Int {
        Int(sqlite3_column_int(statement, index))
    }

    func bind(_ statement: OpaquePointer, _ index: Int32, _ value: String) {
        _ = value.withCString { pointer in
            sqlite3_bind_text(statement, index, pointer, -1, Self.transient)
        }
    }

    func bind(_ statement: OpaquePointer, _ index: Int32, _ value: Double) {
        sqlite3_bind_double(statement, index, value)
    }

    func bind(_ statement: OpaquePointer, _ index: Int32, _ value: Int) {
        sqlite3_bind_int(statement, index, Int32(value))
    }

    func bindNull(_ statement: OpaquePointer, _ index: Int32) {
        sqlite3_bind_null(statement, index)
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw CurveDatabaseError.statementFailed(String(cString: sqlite3_errmsg(db)))
        }
        return statement
    }
}

final class SQLiteCurveStore: CurveStore {
    static let curveColumns = """
    id, county, road_name, surface, radius_ft, deflection_deg, \
    rd_class, rd_design, closed_loop, quality_flags, \
    lat, lon, min_lat, max_lat, min_lon, max_lon, coordinates_json
    """

    /// Bounding-box lookup. Callers pass a radius; this never reads the whole table.
    static let nearbySQL = """
    SELECT \(curveColumns) \
    FROM curves \
    WHERE min_lat <= ? AND max_lat >= ? AND min_lon <= ? AND max_lon >= ?
    """

    /// One row by primary key. This is not a table scan.
    static let curveByIDSQL = """
    SELECT \(curveColumns) FROM curves WHERE id = ?
    """

    /// Visible-map lookup. The limit keeps a wide view from reading every curve.
    static let viewportSQL = """
    SELECT \(curveColumns) \
    FROM curves \
    WHERE min_lat <= ? AND max_lat >= ? AND min_lon <= ? AND max_lon >= ? \
    AND quality_flags = '' AND closed_loop = 0 AND radius_ft >= 50 \
    LIMIT ?
    """

    static let viewportPointSQL = """
    SELECT id, county, road_name, surface, radius_ft, deflection_deg, \
    rd_class, rd_design, closed_loop, quality_flags, \
    lat, lon, min_lat, max_lat, min_lon, max_lon, '[]' \
    FROM curves \
    WHERE min_lat <= ? AND max_lat >= ? AND min_lon <= ? AND max_lon >= ? \
    AND quality_flags = '' AND closed_loop = 0 AND radius_ft >= 50 \
    LIMIT ?
    """

    static let searchSQL = """
    SELECT id, county, road_name, surface, radius_ft, deflection_deg, \
    rd_class, rd_design, closed_loop, quality_flags, \
    lat, lon, min_lat, max_lat, min_lon, max_lon, '[]' \
    FROM curves \
    WHERE road_name LIKE ? COLLATE NOCASE \
    AND quality_flags = '' AND closed_loop = 0 AND radius_ft >= 50 \
    LIMIT ?
    """

    static let countySQL = """
    SELECT county, MIN(min_lat), MAX(max_lat), MIN(min_lon), MAX(max_lon), COUNT(*) \
    FROM curves \
    WHERE quality_flags = '' AND closed_loop = 0 AND radius_ft >= 50 \
    GROUP BY county \
    ORDER BY county
    """

    private let connection: SQLiteConnection
    private let lock = NSLock()

    init(databaseURL: URL) throws {
        connection = try SQLiteConnection(url: databaseURL, readonly: true)
    }

    static func openBundled() throws -> SQLiteCurveStore {
        try SQLiteCurveStore(databaseURL: BundledCurves.prepareWritableCopy())
    }

    func curves(nearLatitude latitude: Double, longitude: Double, radiusMeters: Double) -> [Curve] {
        guard radiusMeters > 0, latitude.isFinite, longitude.isFinite else { return [] }
        let span = Geo.degreeSpan(latitude: latitude, radiusMeters: radiusMeters)
        let minLatitude = latitude - span.latitude
        let maxLatitude = latitude + span.latitude
        let minLongitude = longitude - span.longitude
        let maxLongitude = longitude + span.longitude
        lock.lock()
        defer { lock.unlock() }
        do {
            var found: [Curve] = []
            try connection.query(Self.nearbySQL, { statement in
                found.append(self.curve(from: statement))
            }, bind: { statement in
                self.connection.bind(statement, 1, maxLatitude)
                self.connection.bind(statement, 2, minLatitude)
                self.connection.bind(statement, 3, maxLongitude)
                self.connection.bind(statement, 4, minLongitude)
            })
            return found.filter {
                Geo.distanceToCurve(latitude: latitude, longitude: longitude, curve: $0) <= radiusMeters
            }
        } catch {
            print("Curve lookup failed: \(error)")
            return []
        }
    }

    func curves(
        minLatitude: Double,
        maxLatitude: Double,
        minLongitude: Double,
        maxLongitude: Double,
        limit: Int,
        includeCoordinates: Bool
    ) -> [Curve] {
        guard limit > 0, minLatitude <= maxLatitude, minLongitude <= maxLongitude else { return [] }
        return rows(includeCoordinates ? Self.viewportSQL : Self.viewportPointSQL) { statement in
            self.connection.bind(statement, 1, maxLatitude)
            self.connection.bind(statement, 2, minLatitude)
            self.connection.bind(statement, 3, maxLongitude)
            self.connection.bind(statement, 4, minLongitude)
            self.connection.bind(statement, 5, limit)
        }
    }

    func counties() -> [CurveCounty] {
        lock.lock()
        defer { lock.unlock() }
        do {
            var found: [CurveCounty] = []
            try connection.query(Self.countySQL) { statement in
                found.append(CurveCounty(
                    name: self.connection.text(statement, 0),
                    minLatitude: self.connection.double(statement, 1),
                    maxLatitude: self.connection.double(statement, 2),
                    minLongitude: self.connection.double(statement, 3),
                    maxLongitude: self.connection.double(statement, 4),
                    count: self.connection.int(statement, 5)
                ))
            }
            return found
        } catch {
            print("County lookup failed: \(error)")
            return []
        }
    }

    func searchRoads(_ query: String, limit: Int) -> [Curve] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, limit > 0 else { return [] }
        let pattern = "%\(trimmed.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: "_", with: ""))%"
        return rows(Self.searchSQL) { statement in
            self.connection.bind(statement, 1, pattern)
            self.connection.bind(statement, 2, limit)
        }
    }

    private func rows(_ sql: String, bind: (OpaquePointer) -> Void) -> [Curve] {
        lock.lock()
        defer { lock.unlock() }
        do {
            var found: [Curve] = []
            try connection.query(sql, { statement in
                found.append(self.curve(from: statement))
            }, bind: bind)
            return found
        } catch {
            print("Curve lookup failed: \(error)")
            return []
        }
    }

    func curve(id: String) -> Curve? {
        lock.lock()
        defer { lock.unlock() }
        do {
            var found: Curve?
            try connection.query(Self.curveByIDSQL, { statement in
                found = self.curve(from: statement)
            }, bind: { statement in
                self.connection.bind(statement, 1, id)
            })
            return found
        } catch {
            print("Curve id lookup failed: \(error)")
            return nil
        }
    }

    private func curve(from statement: OpaquePointer) -> Curve {
        let coordinates = coordinates(from: connection.text(statement, 16))
        let surface = roadSurface(from: connection.text(statement, 3))
        return Curve(
            id: connection.text(statement, 0),
            county: connection.text(statement, 1),
            roadName: connection.text(statement, 2),
            surface: surface,
            radiusFeet: connection.double(statement, 4),
            deflectionDegrees: connection.double(statement, 5),
            qualityFlags: connection.text(statement, 9),
            roadClass: connection.text(statement, 6),
            roadDesign: connection.text(statement, 7),
            closedLoop: connection.int(statement, 8) != 0,
            latitude: connection.double(statement, 10),
            longitude: connection.double(statement, 11),
            minLatitude: connection.double(statement, 12),
            maxLatitude: connection.double(statement, 13),
            minLongitude: connection.double(statement, 14),
            maxLongitude: connection.double(statement, 15),
            coordinates: coordinates
        )
    }

    private func coordinates(from json: String) -> [MapPoint] {
        guard let data = json.data(using: .utf8),
              let pairs = try? JSONSerialization.jsonObject(with: data) as? [[Double]] else {
            return []
        }
        return pairs.compactMap { pair in
            guard pair.count >= 2 else { return nil }
            return MapPoint(longitude: pair[0], latitude: pair[1])
        }
    }
}
