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
                apparentTiltDegrees: nil,
                direction: row.pass.direction,
                hourBucket: row.pass.hourBucket
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
    /// Passes wait here until the trip ends, so uploads carry no timing that traces the drive.
    private var pendingUploads: [AnonymousPassBody] = []
    private var lastHandledAt: Date?
    private var gpsWatchdog: Timer?
    private let places: RiderPlaceLookup
    /// No fix for this long means location stopped, not that the road went quiet.
    static let gpsSilenceSeconds: TimeInterval = 4

    init(
        engine: TripEngine,
        bridge: TripScreenBridge,
        curves: SQLiteCurveStore,
        startSensors: Bool = true,
        camera: DashRunning? = nil,
        uploader: PassSending = PassUpload(),
        places: RiderPlaceLookup = RiderPlaceLookup()
    ) {
        self.engine = engine
        self.bridge = bridge
        self.curves = curves
        self.startSensors = startSensors
        self.camera = camera ?? DashCamera()
        self.uploader = uploader
        self.places = places
        connect()
    }

    private func connect() {
        engine.dashEnabled = false
        camera.onChange = { [weak self] reading in
            self?.apply(reading)
        }
        let onStart: (DriverMode, Bool) -> Void = { [weak self] mode, upload in
            guard let self else { return }
            self.engine.uploadOptIn = upload
            self.engine.dashEnabled = mode == .under18 ? false : DashPreference.isOn
            self.reading = DashReading(camera: nil, vision: .quiet, state: self.engine.dashEnabled ? .unconfirmed : .off, acceptedAt: nil)
            self.lastUpdate = nil
            self.lastCurve = nil
            self.pendingUploads = []
            do {
                try self.engine.beginTrip(driverMode: mode, startSensors: self.startSensors)
            } catch {
                self.assignDrive(self.snapshot(
                    curve: nil,
                    distance: nil,
                    gps: "Trip did not start",
                    paused: false,
                    range: nil
                ))
                return
            }
            self.syncCamera(mode: mode, paused: false)
            self.publishIdle()
            self.startGPSWatchdog()
        }
        let onPause: (Bool) -> Void = { [weak self] paused in
            guard let self else { return }
            if paused {
                self.engine.pause()
            } else {
                self.engine.resume()
            }
            self.lastHandledAt = nil
            self.syncCamera(mode: self.engine.snapshot.driverMode, paused: paused)
            self.publishPause()
        }
        let onFinish: () -> Void = { [weak self] in
            self?.finish()
        }
        let onUpload: (Bool) -> Void = { [weak self] upload in
            self?.engine.uploadOptIn = upload
            if !upload { self?.pendingUploads = [] }
        }
        let onDelete: () throws -> Void = { [weak self] in
            guard let self else { return }
            self.camera.stop()
            self.reading = DashReading(camera: nil, vision: .quiet, state: .off, acceptedAt: nil)
            self.pendingUploads = []
            try self.engine.deletePassHistory()
            self.publishTiming()
        }
        engine.onHandled = { [weak self] update, curve in
            guard let self else { return }
            self.lastHandledAt = Date()
            if update.gate.allowsUpload {
                let version = PassUpload.appVersion
                for pass in update.completed {
                    if let body = AnonymousPass.body(from: pass, appVersion: version) {
                        self.pendingUploads.append(body)
                    }
                }
            }
            self.publishDrive(update, curve: curve)
        }
        engine.onLocationAuthorization = { [weak self] in
            guard let self, self.engine.snapshot.tripID != nil, !self.engine.snapshot.paused else { return }
            let banner = self.engine.waitingStatus()
            guard banner != "Waiting for location" else { return }
            guard self.lastUpdate?.gpsGood != true else { return }
            self.publishIdle()
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
        stopGPSWatchdog()
        flushUploads()
        camera.stop()
        let debrief = (try? engine.debrief(curves: curves)) ?? TripScreenDebrief()
        engine.endTrip()
        reading = DashReading(camera: nil, vision: .quiet, state: .off, acceptedAt: nil)
        publishDebrief(debrief)
        publishTiming()
    }

    /// Sends the trip's passes once, in random order, if uploads are still on.
    private func flushUploads() {
        let batch = pendingUploads.shuffled()
        pendingUploads = []
        guard engine.uploadOptIn else { return }
        for body in batch { uploader.send(body) }
    }

    private func startGPSWatchdog() {
        gpsWatchdog?.invalidate()
        lastHandledAt = nil
        gpsWatchdog = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.checkGPSSilence()
        }
    }

    private func stopGPSWatchdog() {
        gpsWatchdog?.invalidate()
        gpsWatchdog = nil
        lastHandledAt = nil
    }

    /// If fixes stop arriving, the last curve and distance are stale. Say so instead of freezing on them.
    private func checkGPSSilence() {
        guard let last = lastHandledAt, engine.snapshot.tripID != nil, !engine.snapshot.paused,
              Date().timeIntervalSince(last) > Self.gpsSilenceSeconds else { return }
        lastHandledAt = nil
        lastUpdate = nil
        lastCurve = nil
        camera.noteMatchedSurface(nil)
        camera.noteCurveApproach(nil)
        assignDrive(snapshot(
            curve: nil,
            distance: nil,
            gps: "No GPS signal. Warnings paused.",
            paused: false,
            range: nil
        ))
    }

    private func apply(_ reading: DashReading) {
        let previous = self.reading
        self.reading = reading
        // The engine needs every frame to keep the evidence fresh. The screen only needs a change.
        engine.updateVision(reading.vision, camera: reading.camera, acceptedAt: reading.acceptedAt ?? Date())
        guard showsDifferently(previous, reading) else { return }
        if let lastUpdate {
            publishDrive(lastUpdate, curve: lastCurve)
        } else {
            publishIdle()
        }
    }

    private func showsDifferently(_ old: DashReading, _ new: DashReading) -> Bool {
        let threshold = DriveRules.materialConfidence
        return old.state != new.state
            || old.vision != new.vision
            || old.camera?.label != new.camera?.label
            || (old.camera.map { $0.confidence >= threshold }) != (new.camera.map { $0.confidence >= threshold })
    }

    private func publishDrive(_ update: TripUpdate, curve: Curve?) {
        lastUpdate = update
        lastCurve = curve
        camera.noteMatchedSurface(update.gpsGood ? curve?.surface : nil)
        for pass in update.completed {
            camera.noteCurvePassed(pass.curveID)
        }
        camera.noteCurveApproach(update.gpsGood ? update.matchedCurveID : nil)
        let showCurve = update.gpsGood && curve != nil && engine.snapshot.driverMode != .under18
        let place = standingPlace(for: update)
        assignDrive(snapshot(
            curve: showCurve ? curve : nil,
            distance: showCurve ? update.distanceMeters : nil,
            gps: update.gpsStatus,
            measured: update.measuredSpeedMPH,
            prompt: update.promptSpeedMPH,
            paused: engine.snapshot.paused,
            range: showCurve ? update.screeningRange : nil,
            advisoryNotice: showCurve ? update.advisoryNotice : nil,
            advisoryWarning: showCurve ? update.advisoryWarning : nil,
            placeTitle: place?.title,
            placeDetail: place?.detail,
            latitude: update.latitude,
            longitude: update.longitude
        ))
        refreshStandingPlace(for: update)
    }

    private func standingPlace(for update: TripUpdate) -> RiderPlace? {
        guard update.gpsStatus == "Standing still",
              let latitude = update.latitude,
              let longitude = update.longitude else { return nil }
        return places.immediate(latitude: latitude, longitude: longitude)
    }

    /// Replaces the coordinate with a street and town when the geocoder answers.
    /// A second pass finds the saved name and does not ask again.
    private func refreshStandingPlace(for update: TripUpdate) {
        guard update.gpsStatus == "Standing still",
              let latitude = update.latitude,
              let longitude = update.longitude else { return }
        places.resolve(latitude: latitude, longitude: longitude) { [weak self] in
            guard let self, let last = self.lastUpdate, last.gpsStatus == "Standing still" else { return }
            self.publishDrive(last, curve: self.lastCurve)
        }
    }

    private func publishIdle() {
        assignDrive(snapshot(
            curve: nil,
            distance: nil,
            gps: engine.waitingStatus(),
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
        return allowsCamera ? "Camera on" : "Camera off"
    }

    private func snapshot(
        curve: Curve?,
        distance: Double?,
        gps: String,
        measured: Double? = nil,
        prompt: Double? = nil,
        paused: Bool,
        range: ScreeningRange?,
        advisoryNotice: String? = nil,
        advisoryWarning: Bool? = nil,
        placeTitle: String? = nil,
        placeDetail: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) -> DriveScreenSnapshot {
        DriveScreenSnapshot(
            nextCurve: curve,
            distanceMeters: distance,
            cameraEvidence: reading.camera,
            cameraThreshold: DriveRules.materialConfidence,
            cameraStatus: cameraStatus,
            gpsStatus: gps,
            measuredSpeedMPH: measured,
            placeTitle: placeTitle,
            placeDetail: placeDetail,
            latitude: latitude,
            longitude: longitude,
            promptSpeedMPH: prompt,
            isPaused: paused,
            screeningRange: range,
            tripTitle: tripTitle,
            advisoryNotice: advisoryNotice,
            advisoryWarning: advisoryWarning,
            cameraRunning: engine.dashEnabled && reading.state == .running && !paused
        )
    }

    private var cameraStatus: String {
        guard engine.dashEnabled else { return "Camera check is off" }
        switch reading.state {
        case .running:
            return "Camera check is on"
        case .off, .unconfirmed:
            return "Using road records"
        }
    }

    private func publishPause() {
        if let lastUpdate {
            publishDrive(lastUpdate, curve: lastCurve)
        } else {
            publishIdle()
        }
    }

    private func publishDebrief(_ debrief: TripScreenDebrief) {
        hop { self.bridge.debrief = debrief }
    }

    private func publishTiming() {
        let note = engine.timingNote()
        hop { self.bridge.timingNote = note }
    }

    private func assignDrive(_ snapshot: DriveScreenSnapshot) {
        let showsDetails = engine.snapshot.driverMode == .adult
        hop {
            self.bridge.drive = snapshot
            self.bridge.cameraPreview = snapshot.cameraRunning ? self.camera.previewSession : nil
            if showsDetails { DriveLiveActivity.render(snapshot, speaks: true) }
        }
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
