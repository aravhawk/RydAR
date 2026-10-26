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
            LockScreenCard(
                headline: context.state.headline,
                detail: context.state.detail,
                compact: context.state.compact,
                alerting: context.state.alerting
            )
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
                        .foregroundStyle(context.state.alerting ? Color.orange : Color.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.headline)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(context.state.detail)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: context.state.alerting ? "exclamationmark.triangle.fill" : "arrow.turn.up.right")
                    .foregroundStyle(context.state.alerting ? Color.orange : Color.teal)
            } compactTrailing: {
                Text(context.state.compact)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(context.state.alerting ? Color.orange : Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            } minimal: {
                Image(systemName: context.state.alerting ? "exclamationmark.triangle.fill" : "arrow.turn.up.right")
                    .foregroundStyle(context.state.alerting ? Color.orange : Color.teal)
            }
        }
    }
}

/// Light card, dark type. The Lock Screen follows the wallpaper, so default text
/// was white on this near-white fill and the words disappeared.
private struct LockScreenCard: View {
    var headline: String
    var detail: String
    var compact: String
    var alerting: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("RydAR")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color(red: 0.0, green: 0.40, blue: 0.48))
                Text(headline)
                    .font(.headline)
                    .foregroundStyle(Color.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Color.black.opacity(0.62))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 8)
            Text(compact)
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(alerting ? Color(red: 0.72, green: 0.28, blue: 0.0) : Color.black)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .activityBackgroundTint(alerting
            ? Color(red: 1.0, green: 0.94, blue: 0.88)
            : Color(white: 0.97))
    }
}
