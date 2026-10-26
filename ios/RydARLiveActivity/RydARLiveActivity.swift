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
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("RydAR")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.teal)
                    Text(context.state.headline)
                        .font(.headline)
                        .lineLimit(1)
                    Text(context.state.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(context.state.compact)
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundStyle(context.state.alerting ? Color.orange : Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .activityBackgroundTint(context.state.alerting ? Color.orange.opacity(0.18) : .clear)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("RydAR")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.teal)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.compact)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(context.state.alerting ? Color.orange : Color.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.headline)
                        .font(.headline)
                        .lineLimit(1)
                    Text(context.state.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: context.state.alerting ? "exclamationmark.triangle.fill" : "arrow.turn.up.right")
                    .foregroundStyle(context.state.alerting ? Color.orange : Color.teal)
            } compactTrailing: {
                Text(context.state.compact)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(context.state.alerting ? Color.orange : Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            } minimal: {
                Image(systemName: context.state.alerting ? "exclamationmark.triangle.fill" : "arrow.turn.up.right")
                    .foregroundStyle(context.state.alerting ? Color.orange : Color.teal)
            }
        }
    }
}
