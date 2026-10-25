import ActivityKit
import Foundation

struct DriveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var headline: String
        var detail: String
        var alerting: Bool
    }

    var started: Date
}
