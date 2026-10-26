import ActivityKit
import Foundation

enum DriveLiveActivity {
    private static var last: DriveActivityAttributes.ContentState?
    private static var active = false

    static func begin(speaks: Bool) {
        active = true
        if last == nil { last = waiting(speaks: speaks) }
        Task { @MainActor in
            for activity in Activity<DriveActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
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
        guard active else { return }
        update(state)
    }

    static func end() {
        active = false
        last = nil
        Task { @MainActor in
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
                detail: "No voice on this trip.",
                compact: "Quiet",
                alerting: false
            )
        }
        return DriveActivityAttributes.ContentState(
            headline: "Listening",
            detail: "Watching for a curve.",
            compact: "On",
            alerting: false
        )
    }

    private static func content(_ drive: DriveScreenSnapshot, speaks: Bool) -> DriveActivityAttributes.ContentState {
        if !speaks { return waiting(speaks: false) }
        if drive.isPaused {
            return DriveActivityAttributes.ContentState(
                headline: "Paused",
                detail: "Alerts are quiet.",
                compact: "Paused",
                alerting: false
            )
        }
        if let curve = drive.nextCurve {
            let road = curve.roadName.isEmpty ? "Curve ahead" : curve.roadName
            let above = aboveAdvisory(drive)
            let advisory = drive.screeningRange.map {
                "\(format($0.low))–\(format($0.high)) mph"
            } ?? "advisory speed"
            let detail = above ? "Above advisory · \(advisory)" : "Advisory \(advisory)"
            let compact = drive.distanceMeters.map { "\(bucketDistance($0)) m" } ?? "Curve"
            return DriveActivityAttributes.ContentState(
                headline: road,
                detail: detail,
                compact: compact,
                alerting: above
            )
        }
        if let speed = drive.measuredSpeedMPH {
            return DriveActivityAttributes.ContentState(
                headline: "No curve ahead",
                detail: drive.gpsStatus,
                compact: "\(bucketSpeed(speed)) mph",
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

    private static func aboveAdvisory(_ drive: DriveScreenSnapshot) -> Bool {
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

    private static func format(_ mph: Double) -> String {
        String(format: "%.0f", mph.rounded())
    }
}
