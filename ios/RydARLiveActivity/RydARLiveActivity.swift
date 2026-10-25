import ActivityKit
import SwiftUI
import WidgetKit

@main
struct RydARLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        RydARLiveActivity()
    }
}

struct RydARLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DriveActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 4) {
                Text("RydAR")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.teal)
                Text(context.state.headline)
                    .font(.headline)
                Text(context.state.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .activityBackgroundTint(Color(white: 0.96))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("RydAR")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.teal)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: context.state.alerting ? "speaker.wave.2.fill" : "arrow.turn.up.right")
                        .foregroundStyle(.teal)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.headline)
                        .font(.headline)
                    Text(context.state.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "arrow.turn.up.right")
                    .foregroundStyle(.teal)
            } compactTrailing: {
                Text(context.state.alerting ? "Curve" : "On")
                    .font(.caption.weight(.semibold))
            } minimal: {
                Image(systemName: "arrow.turn.up.right")
                    .foregroundStyle(.teal)
            }
        }
    }
}
