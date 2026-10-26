import Foundation

struct CompletedPass: Equatable {
    var curveID: String
    var direction: String
    var effectiveSpeedMPH: Double
    var vLoMPH: Double
    var vHiMPH: Double
    var spoke: Bool
    var hourBucket: Int
    var late: Bool
    var surfaceUsed: RoadSurface
    var radiusBand: String
    var lookAheadMeters: Double
    var contextKey: String
    var brakingDistanceMeters: Double? = nil
}

struct StoredPass: Equatable {
    var id: String
    var tripID: String
    var pass: CompletedPass
}

struct TripRecord: Equatable {
    var id: String
    var startedAt: String
    var driverMode: DriverMode
    var notes: String?
}

struct ContextCount: Equatable {
    var key: String
    var latePasses: Int
    var earlyPasses: Int
}

/// Braking onset inside the base look-ahead, or speed still above vLo inside 40 m.
/// The onset test is strict: braking exactly at the look-ahead distance is the start
/// of the window, not inside it.
func passWasLate(
    brakingOnsetDistanceMeters: Double?,
    baseLookAheadMeters: Double,
    fastAboveRangeInsideFortyMeters: Bool
) -> Bool {
    if let onset = brakingOnsetDistanceMeters, onset < baseLookAheadMeters {
        return true
    }
    return fastAboveRangeInsideFortyMeters
}

/// Uses lookAheadMeters at 20 m/s, where the 1.4 factor stays under the 450 m cap.
func contextSaysLate(_ memory: ApproachMemory) -> Bool {
    let quiet = VisionCaution(standingWaterOrSnow: false, severeUnevenOnPaved: false)
    let speed = 20.0
    return lookAheadMeters(speedMps: speed, memory: memory, vision: quiet)
        > baseLookAheadMeters(speedMps: speed) + 0.001
}

final class PassLog {
    private let connection: SQLiteConnection
    private let lock = NSLock()
    private let dates = ISO8601DateFormatter()

    init(databaseURL: URL) throws {
        connection = try SQLiteConnection(url: databaseURL, readonly: false)
        try connection.execute("PRAGMA foreign_keys = ON;")
        try connection.execute("PRAGMA journal_mode=WAL;")
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS trips (
              id TEXT PRIMARY KEY,
              started_at TEXT NOT NULL,
              driver_mode TEXT NOT NULL,
              notes TEXT
            );
            CREATE TABLE IF NOT EXISTS trip_passes (
              id TEXT PRIMARY KEY,
              trip_id TEXT NOT NULL,
              curve_id TEXT NOT NULL,
              direction TEXT,
              v_eff_mph REAL,
              v_lo_mph REAL,
              v_hi_mph REAL,
              spoke INTEGER NOT NULL DEFAULT 0,
              hour_bucket INTEGER,
              late INTEGER NOT NULL DEFAULT 0,
              surface_used TEXT,
              radius_band TEXT,
              look_ahead_m REAL,
              braking_m REAL,
              FOREIGN KEY (trip_id) REFERENCES trips (id)
            );
            CREATE TABLE IF NOT EXISTS approach_memory (
              context_key TEXT PRIMARY KEY,
              late_passes INTEGER NOT NULL DEFAULT 0,
              early_passes INTEGER NOT NULL DEFAULT 0,
              onset_count INTEGER NOT NULL DEFAULT 0,
              onset_sum_m REAL NOT NULL DEFAULT 0
            );
            CREATE TABLE IF NOT EXISTS curve_memory (
              curve_id TEXT PRIMARY KEY,
              late_passes INTEGER NOT NULL DEFAULT 0,
              early_passes INTEGER NOT NULL DEFAULT 0,
              onset_count INTEGER NOT NULL DEFAULT 0,
              onset_sum_m REAL NOT NULL DEFAULT 0
            );
            """
        )
        try connection.execute("DROP TABLE IF EXISTS approach_model;")
        try ensureBrakingColumn()
        try ensureOnsetColumns()
    }

    /// Copies made before braking distance was stored still open.
    private func ensureBrakingColumn() throws {
        var names: [String] = []
        try connection.query("PRAGMA table_info(trip_passes)") { statement in
            names.append(self.connection.text(statement, 1))
        }
        if !names.contains("braking_m") {
            try connection.execute("ALTER TABLE trip_passes ADD COLUMN braking_m REAL;")
        }
    }

    private func ensureOnsetColumns() throws {
        for table in ["approach_memory", "curve_memory"] {
            var names: [String] = []
            try connection.query("PRAGMA table_info(\(table))") { statement in
                names.append(self.connection.text(statement, 1))
            }
            if !names.contains("onset_count") {
                try connection.execute("ALTER TABLE \(table) ADD COLUMN onset_count INTEGER NOT NULL DEFAULT 0;")
            }
            if !names.contains("onset_sum_m") {
                try connection.execute("ALTER TABLE \(table) ADD COLUMN onset_sum_m REAL NOT NULL DEFAULT 0;")
            }
        }
    }

    func startTrip(mode: DriverMode, at date: Date = Date(), notes: String? = nil) throws -> String {
        let id = UUID().uuidString
        let started = dates.string(from: date)
        lock.lock()
        defer { lock.unlock() }
        try connection.run(
            "INSERT INTO trips (id, started_at, driver_mode, notes) VALUES (?, ?, ?, ?)"
        ) { statement in
            connection.bind(statement, 1, id)
            connection.bind(statement, 2, started)
            connection.bind(statement, 3, mode.rawValue)
            if let notes {
                connection.bind(statement, 4, notes)
            } else {
                connection.bindNull(statement, 4)
            }
        }
        return id
    }

    func trip(id: String) throws -> TripRecord? {
        lock.lock()
        defer { lock.unlock() }
        var found: TripRecord?
        try connection.query(
            "SELECT id, started_at, driver_mode, notes FROM trips WHERE id = ?",
            { statement in
                guard let mode = DriverMode(rawValue: self.connection.text(statement, 2)) else { return }
                let notes = self.connection.isNull(statement, 3) ? nil : self.connection.text(statement, 3)
                found = TripRecord(
                    id: self.connection.text(statement, 0),
                    startedAt: self.connection.text(statement, 1),
                    driverMode: mode,
                    notes: notes
                )
            },
            bind: { statement in
                self.connection.bind(statement, 1, id)
            }
        )
        return found
    }

    func record(_ pass: CompletedPass, tripID: String) throws {
        let id = UUID().uuidString
        lock.lock()
        defer { lock.unlock() }
        try connection.execute("BEGIN IMMEDIATE")
        do {
            let onsetCount = pass.brakingDistanceMeters == nil ? 0 : 1
            let onsetSum = pass.brakingDistanceMeters ?? 0
            try connection.run(
                """
                INSERT INTO trip_passes (
                  id, trip_id, curve_id, direction, v_eff_mph, v_lo_mph, v_hi_mph,
                  spoke, hour_bucket, late, surface_used, radius_band, look_ahead_m, braking_m
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """
            ) { statement in
                connection.bind(statement, 1, id)
                connection.bind(statement, 2, tripID)
                connection.bind(statement, 3, pass.curveID)
                connection.bind(statement, 4, pass.direction)
                connection.bind(statement, 5, pass.effectiveSpeedMPH)
                connection.bind(statement, 6, pass.vLoMPH)
                connection.bind(statement, 7, pass.vHiMPH)
                connection.bind(statement, 8, pass.spoke ? 1 : 0)
                connection.bind(statement, 9, pass.hourBucket)
                connection.bind(statement, 10, pass.late ? 1 : 0)
                connection.bind(statement, 11, pass.surfaceUsed.rawValue)
                connection.bind(statement, 12, pass.radiusBand)
                connection.bind(statement, 13, pass.lookAheadMeters)
                if let braking = pass.brakingDistanceMeters {
                    connection.bind(statement, 14, braking)
                } else {
                    connection.bindNull(statement, 14)
                }
            }
            try connection.run(
                """
                INSERT INTO approach_memory (
                  context_key, late_passes, early_passes, onset_count, onset_sum_m
                ) VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(context_key) DO UPDATE SET
                  late_passes = late_passes + excluded.late_passes,
                  early_passes = early_passes + excluded.early_passes,
                  onset_count = onset_count + excluded.onset_count,
                  onset_sum_m = onset_sum_m + excluded.onset_sum_m
                """
            ) { statement in
                connection.bind(statement, 1, pass.contextKey)
                connection.bind(statement, 2, pass.late ? 1 : 0)
                connection.bind(statement, 3, pass.late ? 0 : 1)
                connection.bind(statement, 4, onsetCount)
                connection.bind(statement, 5, onsetSum)
            }
            try connection.run(
                """
                INSERT INTO curve_memory (
                  curve_id, late_passes, early_passes, onset_count, onset_sum_m
                ) VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(curve_id) DO UPDATE SET
                  late_passes = late_passes + excluded.late_passes,
                  early_passes = early_passes + excluded.early_passes,
                  onset_count = onset_count + excluded.onset_count,
                  onset_sum_m = onset_sum_m + excluded.onset_sum_m
                """
            ) { statement in
                connection.bind(statement, 1, pass.curveID)
                connection.bind(statement, 2, pass.late ? 1 : 0)
                connection.bind(statement, 3, pass.late ? 0 : 1)
                connection.bind(statement, 4, onsetCount)
                connection.bind(statement, 5, onsetSum)
            }
            try connection.execute("COMMIT")
        } catch {
            try? connection.execute("ROLLBACK")
            throw error
        }
    }

    func memory(for contextKey: String) throws -> ApproachMemory {
        lock.lock()
        defer { lock.unlock() }
        return try memoryLocked(contextKey)
    }

    func curveMemory(for curveID: String) throws -> ApproachMemory {
        lock.lock()
        defer { lock.unlock() }
        return try curveMemoryLocked(curveID)
    }

    func onset(forContext contextKey: String) throws -> OnsetMemory {
        lock.lock()
        defer { lock.unlock() }
        return try onsetLocked(table: "approach_memory", column: "context_key", key: contextKey)
    }

    func onset(forCurve curveID: String) throws -> OnsetMemory {
        lock.lock()
        defer { lock.unlock() }
        return try onsetLocked(table: "curve_memory", column: "curve_id", key: curveID)
    }

    func curvesWithEarlierPrompt() throws -> Int {
        lock.lock()
        defer { lock.unlock() }
        let reference = baseLookAheadMeters(speedMps: 20)
        var count = 0
        try connection.query(
            "SELECT late_passes, early_passes, onset_count, onset_sum_m FROM curve_memory"
        ) { statement in
            let counts = ApproachMemory(
                latePasses: self.connection.int(statement, 0),
                earlyPasses: self.connection.int(statement, 1)
            )
            let onset = OnsetMemory(
                count: self.connection.int(statement, 2),
                sumMeters: self.connection.double(statement, 3)
            )
            let placed = placedLookAheadMeters(
                baseMeters: reference, context: ApproachMemory(latePasses: 0, earlyPasses: 0),
                curve: counts, curveOnset: onset
            )
            if placed > reference + 0.5 { count += 1 }
        }
        return count
    }

    private func memoryLocked(_ contextKey: String) throws -> ApproachMemory {
        var memory = ApproachMemory(latePasses: 0, earlyPasses: 0)
        try connection.query(
            "SELECT late_passes, early_passes FROM approach_memory WHERE context_key = ?",
            { statement in
                memory = ApproachMemory(
                    latePasses: self.connection.int(statement, 0),
                    earlyPasses: self.connection.int(statement, 1)
                )
            },
            bind: { statement in
                self.connection.bind(statement, 1, contextKey)
            }
        )
        return memory
    }

    private func curveMemoryLocked(_ curveID: String) throws -> ApproachMemory {
        var memory = ApproachMemory(latePasses: 0, earlyPasses: 0)
        try connection.query(
            "SELECT late_passes, early_passes FROM curve_memory WHERE curve_id = ?",
            { statement in
                memory = ApproachMemory(
                    latePasses: self.connection.int(statement, 0),
                    earlyPasses: self.connection.int(statement, 1)
                )
            },
            bind: { statement in
                self.connection.bind(statement, 1, curveID)
            }
        )
        return memory
    }

    private func onsetLocked(table: String, column: String, key: String) throws -> OnsetMemory {
        var onset = OnsetMemory.empty
        try connection.query(
            "SELECT onset_count, onset_sum_m FROM \(table) WHERE \(column) = ?",
            { statement in
                onset = OnsetMemory(
                    count: self.connection.int(statement, 0),
                    sumMeters: self.connection.double(statement, 1)
                )
            },
            bind: { statement in
                self.connection.bind(statement, 1, key)
            }
        )
        return onset
    }

    func passesUnderRange(curveID: String) throws -> Int {
        lock.lock()
        defer { lock.unlock() }
        var count = 0
        try connection.query(
            "SELECT COUNT(*) FROM trip_passes WHERE curve_id = ? AND v_eff_mph <= v_lo_mph",
            { statement in
                count = self.connection.int(statement, 0)
            },
            bind: { statement in
                self.connection.bind(statement, 1, curveID)
            }
        )
        return count
    }

    func passes(forTrip tripID: String) throws -> [StoredPass] {
        lock.lock()
        defer { lock.unlock() }
        var rows: [StoredPass] = []
        try connection.query(
            """
            SELECT id, trip_id, curve_id, direction, v_eff_mph, v_lo_mph, v_hi_mph,
                   spoke, hour_bucket, late, surface_used, radius_band, look_ahead_m, braking_m
            FROM trip_passes WHERE trip_id = ? ORDER BY rowid
            """,
            { statement in
                rows.append(self.storedPass(from: statement))
            },
            bind: { statement in
                self.connection.bind(statement, 1, tripID)
            }
        )
        return rows
    }

    func overRangePasses(forTrip tripID: String) throws -> [StoredPass] {
        try passes(forTrip: tripID)
            .filter { $0.pass.effectiveSpeedMPH > $0.pass.vLoMPH }
            .sorted { lhs, rhs in
                let leftGap = lhs.pass.effectiveSpeedMPH - lhs.pass.vLoMPH
                let rightGap = rhs.pass.effectiveSpeedMPH - rhs.pass.vLoMPH
                if leftGap == rightGap { return lhs.pass.curveID < rhs.pass.curveID }
                return leftGap > rightGap
            }
    }

    func contexts() throws -> [ContextCount] {
        lock.lock()
        defer { lock.unlock() }
        var rows: [ContextCount] = []
        try connection.query(
            "SELECT context_key, late_passes, early_passes FROM approach_memory ORDER BY context_key",
            { statement in
                rows.append(
                    ContextCount(
                        key: self.connection.text(statement, 0),
                        latePasses: self.connection.int(statement, 1),
                        earlyPasses: self.connection.int(statement, 2)
                    )
                )
            }
        )
        return rows
    }

    func lateContexts() throws -> [ContextCount] {
        try contexts()
            .filter {
                contextSaysLate(ApproachMemory(latePasses: $0.latePasses, earlyPasses: $0.earlyPasses))
            }
            .sorted { $0.latePasses > $1.latePasses }
    }

    /// Clears trips and timing memory. The curve table stays.
    func deleteAll() throws {
        lock.lock()
        defer { lock.unlock() }
        try connection.execute("DELETE FROM trip_passes;")
        try connection.execute("DELETE FROM approach_memory;")
        try connection.execute("DELETE FROM curve_memory;")
        try connection.execute("DELETE FROM trips;")
    }

    private func storedPass(from statement: OpaquePointer) -> StoredPass {
        let surface = RoadSurface(rawValue: connection.text(statement, 10)) ?? .unpaved
        let band = connection.text(statement, 11)
        let hour = connection.int(statement, 8)
        let key = approachContextKey(surface: surface, radiusFeet: feet(forBand: band), hour: hour)
        let pass = CompletedPass(
            curveID: connection.text(statement, 2),
            direction: connection.text(statement, 3),
            effectiveSpeedMPH: connection.double(statement, 4),
            vLoMPH: connection.double(statement, 5),
            vHiMPH: connection.double(statement, 6),
            spoke: connection.int(statement, 7) != 0,
            hourBucket: hour,
            late: connection.int(statement, 9) != 0,
            surfaceUsed: surface,
            radiusBand: band,
            lookAheadMeters: connection.double(statement, 12),
            contextKey: key,
            brakingDistanceMeters: connection.isNull(statement, 13) ? nil : connection.double(statement, 13)
        )
        return StoredPass(id: connection.text(statement, 0), tripID: connection.text(statement, 1), pass: pass)
    }

    private func feet(forBand band: String) -> Double {
        switch band {
        case "under-150":
            return 100
        case "300-600":
            return 400
        default:
            return 200
        }
    }
}
