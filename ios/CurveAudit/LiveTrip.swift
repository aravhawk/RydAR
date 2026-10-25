import Foundation

/// Builds the parked debrief from this trip's saved rows. Timing stays in lookAheadMeters.
enum LiveTripDebrief {
    static func make(tripID: String, log: PassLog, curves: SQLiteCurveStore) throws -> TripScreenDebrief {
        let stored = try log.passes(forTrip: tripID)
        var contexts: [String: TimingContextSummary] = [:]
        let passes = stored.map { row -> TripCurvePass in
            let curve = curves.curve(id: row.pass.curveID) ?? placeholder(row.pass)
            if contexts[row.pass.contextKey] == nil {
                let memory = (try? log.memory(for: row.pass.contextKey))
                    ?? ApproachMemory(latePasses: 0, earlyPasses: 0)
                contexts[row.pass.contextKey] = TimingContextSummary(
                    surface: row.pass.surfaceUsed,
                    representativeRadiusFeet: feet(forBand: row.pass.radiusBand),
                    hour: row.pass.hourBucket,
                    memory: memory
                )
            }
            return TripCurvePass(
                id: row.id,
                curve: curve,
                effectiveMPH: row.pass.effectiveSpeedMPH,
                range: ScreeningRange(low: row.pass.vLoMPH, high: row.pass.vHiMPH),
                surfaceUsed: row.pass.surfaceUsed
            )
        }
        return TripScreenDebrief(
            tripID: tripID,
            passes: passes,
            contexts: contexts.values.sorted { $0.id < $1.id }
        )
    }

    private static func feet(forBand band: String) -> Double {
        switch band {
        case "under-150":
            return 100
        case "300-600":
            return 400
        default:
            return 200
        }
    }

    private static func placeholder(_ pass: CompletedPass) -> Curve {
        Curve(
            id: pass.curveID,
            county: "",
            roadName: pass.curveID,
            surface: pass.surfaceUsed,
            radiusFeet: feet(forBand: pass.radiusBand),
            deflectionDegrees: 0,
            qualityFlags: "",
            roadClass: "",
            closedLoop: false,
            latitude: 0,
            longitude: 0,
            minLatitude: 0,
            maxLatitude: 0,
            minLongitude: 0,
            maxLongitude: 0,
            coordinates: []
        )
    }
}

/// Holds the engine and the screen bridge for the life of the app.
/// Connecting it does not query every curve and does not load the vision model.
final class LiveTripSession {
    let engine: TripEngine
    let bridge: TripScreenBridge
    let curves: SQLiteCurveStore
    private let startSensors: Bool

    init(engine: TripEngine, bridge: TripScreenBridge, curves: SQLiteCurveStore, startSensors: Bool = true) {
        self.engine = engine
        self.bridge = bridge
        self.curves = curves
        self.startSensors = startSensors
        connect()
    }

    private func connect() {
        engine.dashEnabled = false
        let onStart: (DriverMode, PromptStyle, Bool) -> Void = { [weak self] mode, style, upload in
            guard let self else { return }
            self.engine.promptStyle = style
            self.engine.uploadOptIn = upload
            self.engine.dashEnabled = false
            do {
                try self.engine.beginTrip(driverMode: mode, startSensors: self.startSensors)
            } catch {
                print("Trip did not start: \(error)")
            }
        }
        let onPause: (Bool) -> Void = { [weak self] paused in
            guard let self else { return }
            if paused {
                self.engine.pause()
            } else {
                self.engine.resume()
            }
            self.publishPause(paused)
        }
        let onFinish: () -> Void = { [weak self] in
            self?.finish()
        }
        let onUpload: (Bool) -> Void = { [weak self] upload in
            self?.engine.uploadOptIn = upload
        }
        let onDelete: () throws -> Void = { [weak self] in
            guard let self else { return }
            try self.engine.deletePassHistory()
        }
        engine.onHandled = { [weak self] update, curve in
            self?.publishDrive(update, curve: curve)
        }
        MainActor.assumeIsolated {
            bridge.onStart = onStart
            bridge.onPause = onPause
            bridge.onFinish = onFinish
            bridge.onUploadPreference = onUpload
            bridge.onDeleteAllData = onDelete
        }
    }

    private func finish() {
        let debrief = (try? engine.debrief(curves: curves)) ?? TripScreenDebrief()
        engine.endTrip()
        publishDebrief(debrief)
    }

    private func publishDrive(_ update: TripUpdate, curve: Curve?) {
        let showCurve = update.gpsGood && curve != nil
        let snapshot = DriveScreenSnapshot(
            nextCurve: showCurve ? curve : nil,
            distanceMeters: showCurve ? update.distanceMeters : nil,
            cameraEvidence: nil,
            cameraThreshold: DriveRules.cameraConfidence,
            cameraStatus: "Off · Co-pilot mode",
            gpsStatus: update.gpsGood ? "GPS ready" : "Waiting for location",
            isPaused: engine.snapshot.paused
        )
        assignDrive(snapshot)
    }

    private func publishPause(_ paused: Bool) {
        var snapshot = bridgeDrive()
        snapshot.isPaused = paused
        assignDrive(snapshot)
    }

    private func publishDebrief(_ debrief: TripScreenDebrief) {
        hop { self.bridge.debrief = debrief }
    }

    private func assignDrive(_ snapshot: DriveScreenSnapshot) {
        hop { self.bridge.drive = snapshot }
    }

    private func bridgeDrive() -> DriveScreenSnapshot {
        if Thread.isMainThread {
            return MainActor.assumeIsolated { bridge.drive }
        }
        return DriveScreenSnapshot()
    }

    private func hop(_ body: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(body)
        } else {
            DispatchQueue.main.async {
                MainActor.assumeIsolated(body)
            }
        }
    }
}
