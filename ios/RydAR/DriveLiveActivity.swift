import ActivityKit
import Foundation

/// Orders start and stop so a trip that ends while the previous activity is
/// still closing cannot leave a lock-screen card up, or erase the new one.
struct ActivitySession: Equatable {
    private(set) var generation = 0
    private(set) var active = false

    mutating func begin() -> Int {
        generation += 1
        active = true
        return generation
    }

    mutating func end() -> Int {
        generation += 1
        active = false
        return generation
    }

    func shouldStart(_ token: Int) -> Bool {
        active && token == generation
    }

    func shouldStop(_ token: Int) -> Bool {
        !active && token == generation
    }
}

enum DriveLiveActivity {
    private static var last: DriveActivityAttributes.ContentState?
    private static var session = ActivitySession()

    static func begin(speaks: Bool) {
        let token = session.begin()
        last = waiting(speaks: speaks)
        Task { @MainActor in
            guard session.shouldStart(token) else { return }
            for activity in Activity<DriveActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
                guard session.shouldStart(token) else { return }
            }
            guard session.shouldStart(token) else { return }
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            let state = last ?? waiting(speaks: speaks)
            _ = try? Activity.request(
                attributes: DriveActivityAttributes(started: Date()),
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
        }
    }

    /// Keeps the Lock Screen on the same curve, distance, and speed as the drive screen.
    static func render(_ drive: DriveScreenSnapshot, speaks: Bool) {
        let state = content(drive, speaks: speaks)
        guard state != last else { return }
        last = state
        guard session.active else { return }
        update(state)
    }

    static func end() {
        let token = session.end()
        last = nil
        Task { @MainActor in
            guard session.shouldStop(token) else { return }
            for activity in Activity<DriveActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private static func update(_ state: DriveActivityAttributes.ContentState) {
        Task { @MainActor in
            for activity in Activity<DriveActivityAttributes>.activities {
                await activity.update(ActivityContent(state: state, staleDate: nil))
            }
        }
    }

    private static func waiting(speaks: Bool) -> DriveActivityAttributes.ContentState {
        if !speaks {
            return DriveActivityAttributes.ContentState(
                headline: "Put the phone away.",
                detail: "No spoken warnings on this trip.",
                compact: "Quiet",
                alerting: false
            )
        }
        return DriveActivityAttributes.ContentState(
            headline: "Listening",
            detail: "Watching for curves.",
            compact: "On",
            alerting: false
        )
    }

    private static func content(_ drive: DriveScreenSnapshot, speaks: Bool) -> DriveActivityAttributes.ContentState {
        if !speaks { return waiting(speaks: false) }
        if drive.isPaused {
            return DriveActivityAttributes.ContentState(
                headline: "Paused",
                detail: "Warnings paused.",
                compact: "Paused",
                alerting: false
            )
        }
        if let curve = drive.nextCurve {
            let road = curve.roadName.isEmpty ? "Curve ahead" : curve.roadName
            let above = aboveAdvisory(drive)
            let detail = drive.advisoryNotice ?? "Curve ahead"
            let compact = drive.distanceMeters.map { distanceText(meters: Double(bucketDistance($0))) } ?? "Curve"
            return DriveActivityAttributes.ContentState(
                headline: road,
                detail: detail,
                compact: compact,
                alerting: above
            )
        }
        if drive.gpsStatus == "Standing still" {
            let readout = driveReadout(
                hasCurve: false,
                roadName: nil,
                gpsStatus: drive.gpsStatus,
                measuredSpeedMPH: drive.measuredSpeedMPH,
                placeTitle: drive.placeTitle,
                placeDetail: drive.placeDetail
            )
            let speed = drive.measuredSpeedMPH ?? 0
            return DriveActivityAttributes.ContentState(
                headline: readout.headline,
                detail: readout.locationPin ?? speedText(mph: speed),
                compact: speedText(mph: Double(bucketSpeed(speed))),
                alerting: false
            )
        }
        if let speed = drive.measuredSpeedMPH {
            return DriveActivityAttributes.ContentState(
                headline: "No curve ahead",
                detail: drive.gpsStatus,
                compact: speedText(mph: Double(bucketSpeed(speed))),
                alerting: false
            )
        }
        return DriveActivityAttributes.ContentState(
            headline: drive.gpsStatus,
            detail: "No curve ahead",
            compact: "On",
            alerting: false
        )
    }

    static func aboveAdvisory(_ drive: DriveScreenSnapshot) -> Bool {
        if let warning = drive.advisoryWarning { return warning }
        guard let range = drive.screeningRange else { return false }
        let speed = drive.promptSpeedMPH ?? drive.measuredSpeedMPH
        guard let speed else { return false }
        return speed > range.low
    }

    private static func bucketDistance(_ meters: Double) -> Int {
        max(0, Int((meters / 25).rounded()) * 25)
    }

    private static func bucketSpeed(_ mph: Double) -> Int {
        max(0, Int((mph / 5).rounded()) * 5)
    }
}
