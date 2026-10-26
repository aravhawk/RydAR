import ActivityKit
import Foundation

struct DriveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var headline: String
        var detail: String
        /// Short lock-screen figure: distance, speed, or a one-word state.
        var compact: String
        var alerting: Bool
    }

    var started: Date
}
