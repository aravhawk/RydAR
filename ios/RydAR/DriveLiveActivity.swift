import ActivityKit
import Foundation

enum DriveLiveActivity {
    static func begin(speaks: Bool) {
        let state = content(speaks: speaks, alerting: false, paused: false)
        Task { @MainActor in
            for activity in Activity<DriveActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            let attributes = DriveActivityAttributes(started: Date())
            _ = try? Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
        }
    }

    static func noteCurve(speaks: Bool) {
        let state = content(speaks: speaks, alerting: true, paused: false)
        update(state)
    }

    static func notePaused(speaks: Bool) {
        update(content(speaks: speaks, alerting: false, paused: true))
    }

    static func noteListening(speaks: Bool) {
        update(content(speaks: speaks, alerting: false, paused: false))
    }

    static func end() {
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

    private static func content(speaks: Bool, alerting: Bool, paused: Bool) -> DriveActivityAttributes.ContentState {
        if !speaks {
            return DriveActivityAttributes.ContentState(
                headline: "Put the phone away.",
                detail: "No voice on this trip.",
                alerting: false
            )
        }
        if paused {
            return DriveActivityAttributes.ContentState(
                headline: "Paused",
                detail: "Alerts are quiet until the trip resumes.",
                alerting: false
            )
        }
        if alerting {
            return DriveActivityAttributes.ContentState(
                headline: "Curve ahead",
                detail: "Above advisory speed.",
                alerting: true
            )
        }
        return DriveActivityAttributes.ContentState(
            headline: "Listening",
            detail: "Alerts keep speaking with Maps in front.",
            alerting: false
        )
    }
}
