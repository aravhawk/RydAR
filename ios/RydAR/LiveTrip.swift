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
                surfaceUsed: row.pass.surfaceUsed,
                brakingDistanceMeters: row.pass.brakingDistanceMeters,
                apparentTiltDegrees: nil
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
    let camera: DashRunning
    let uploader: PassSending
    private let startSensors: Bool
    private var reading = DashReading(camera: nil, vision: .quiet, state: .off, acceptedAt: nil)
    private var lastUpdate: TripUpdate?
    private var lastCurve: Curve?

    init(
        engine: TripEngine,
        bridge: TripScreenBridge,
        curves: SQLiteCurveStore,
        startSensors: Bool = true,
        camera: DashRunning? = nil,
        uploader: PassSending = PassUpload()
    ) {
        self.engine = engine
        self.bridge = bridge
        self.curves = curves
        self.startSensors = startSensors
        self.camera = camera ?? DashCamera()
        self.uploader = uploader
        connect()
    }

    private func connect() {
        engine.dashEnabled = false
        camera.onChange = { [weak self] reading in
            self?.apply(reading)
        }
        let onStart: (DriverMode, PromptStyle, Bool) -> Void = { [weak self] mode, style, upload in
            guard let self else { return }
            self.engine.promptStyle = style
            self.engine.uploadOptIn = upload
            self.engine.dashEnabled = mode == .under18 ? false : DashPreference.isOn
            self.reading = DashReading(camera: nil, vision: .quiet, state: self.engine.dashEnabled ? .unconfirmed : .off, acceptedAt: nil)
            self.lastUpdate = nil
            self.lastCurve = nil
            do {
                try self.engine.beginTrip(driverMode: mode, startSensors: self.startSensors)
            } catch {
                print("Trip did not start: \(error)")
            }
            self.syncCamera(mode: mode, paused: false)
            self.publishIdle()
        }
        let onPause: (Bool) -> Void = { [weak self] paused in
            guard let self else { return }
            if paused {
                self.engine.pause()
            } else {
                self.engine.resume()
            }
            self.syncCamera(mode: self.engine.snapshot.driverMode, paused: paused)
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
            self.camera.stop()
            self.reading = DashReading(camera: nil, vision: .quiet, state: .off, acceptedAt: nil)
            try self.engine.deletePassHistory()
            self.publishTiming()
        }
        engine.onHandled = { [weak self] update, curve in
            guard let self else { return }
            if update.gate.allowsUpload {
                let version = PassUpload.appVersion
                for pass in update.completed {
                    if let body = AnonymousPass.body(from: pass, appVersion: version) {
                        self.uploader.send(body)
                    }
                }
            }
            self.publishDrive(update, curve: curve)
        }
        let configured = (uploader as? PassUpload)?.isConfigured ?? true
        MainActor.assumeIsolated {
            bridge.uploadConfigured = configured
            bridge.onStart = onStart
            bridge.onPause = onPause
            bridge.onFinish = onFinish
            bridge.onUploadPreference = onUpload
            bridge.onDeleteAllData = onDelete
        }
        publishTiming()
    }

    private func syncCamera(mode: DriverMode?, paused: Bool) {
        let allows = driveGate(
            mode: mode,
            speedMps: 0,
            dashEnabled: engine.dashEnabled,
            uploadOptIn: engine.uploadOptIn
        ).allowsCamera
        if paused {
            camera.pause()
            return
        }
        if allows {
            camera.start()
        } else {
            camera.stop()
            engine.updateVision(.quiet, camera: nil)
        }
    }

    private func finish() {
        camera.stop()
        let debrief = (try? engine.debrief(curves: curves)) ?? TripScreenDebrief()
        engine.endTrip()
        reading = DashReading(camera: nil, vision: .quiet, state: .off, acceptedAt: nil)
        publishDebrief(debrief)
        publishTiming()
    }

    private func apply(_ reading: DashReading) {
        self.reading = reading
        engine.updateVision(reading.vision, camera: reading.camera, acceptedAt: reading.acceptedAt ?? Date())
        if let lastUpdate {
            publishDrive(lastUpdate, curve: lastCurve)
        } else {
            publishIdle()
        }
    }

    private func publishDrive(_ update: TripUpdate, curve: Curve?) {
        lastUpdate = update
        lastCurve = curve
        camera.noteMatchedSurface(update.gpsGood ? curve?.surface : nil)
        let showCurve = update.gpsGood && curve != nil
        assignDrive(snapshot(
            curve: showCurve ? curve : nil,
            distance: showCurve ? update.distanceMeters : nil,
            gps: update.gpsStatus,
            measured: update.measuredSpeedMPH,
            prompt: update.promptSpeedMPH,
            paused: engine.snapshot.paused,
            range: showCurve ? update.screeningRange : nil
        ))
    }

    private func publishIdle() {
        assignDrive(snapshot(
            curve: nil,
            distance: nil,
            gps: "Waiting for location",
            paused: engine.snapshot.paused,
            range: nil
        ))
    }

    private var tripTitle: String {
        let allowsCamera = driveGate(
            mode: engine.snapshot.driverMode,
            speedMps: 0,
            dashEnabled: engine.dashEnabled,
            uploadOptIn: engine.uploadOptIn
        ).allowsCamera
        return allowsCamera ? "Dash" : "Co-pilot"
    }

    private func snapshot(
        curve: Curve?,
        distance: Double?,
        gps: String,
        measured: Double? = nil,
        prompt: Double? = nil,
        paused: Bool,
        range: ScreeningRange?
    ) -> DriveScreenSnapshot {
        DriveScreenSnapshot(
            nextCurve: curve,
            distanceMeters: distance,
            cameraEvidence: reading.camera,
            cameraThreshold: DriveRules.materialConfidence,
            cameraStatus: cameraStatus,
            gpsStatus: gps,
            measuredSpeedMPH: measured,
            promptSpeedMPH: prompt,
            isPaused: paused,
            screeningRange: range,
            tripTitle: tripTitle
        )
    }

    private var cameraStatus: String {
        guard engine.dashEnabled else { return "Off · Co-pilot mode" }
        switch reading.state {
        case .running:
            return "Dash · camera on"
        case .off, .unconfirmed:
            return "Dash · county road file"
        }
    }

    private func publishPause(_ paused: Bool) {
        var snapshot = bridgeDrive()
        snapshot.isPaused = paused
        assignDrive(snapshot)
    }

    private func publishDebrief(_ debrief: TripScreenDebrief) {
        hop { self.bridge.debrief = debrief }
    }

    private func publishTiming() {
        let note = engine.timingNote()
        hop { self.bridge.timingNote = note }
    }

    private func assignDrive(_ snapshot: DriveScreenSnapshot) {
        let speaks = engine.snapshot.driverMode != .under18
        hop {
            self.bridge.drive = snapshot
            DriveLiveActivity.render(snapshot, speaks: speaks)
        }
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
