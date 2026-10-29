import ActivityKit
import SwiftUI
import UIKit
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

/// Lock Screen card. It leaves the background to the system material and uses semantic
/// colors, so it follows the wallpaper, Dark Mode, and Liquid Glass on iOS 26. An alert
/// only warms the tint.
private struct LockScreenCard: View {
    var headline: String
    var detail: String
    var compact: String
    var alerting: Bool

    private static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? .systemTeal
            : UIColor(red: 0.0, green: 0.40, blue: 0.48, alpha: 1)
    })
    private static let warning = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? .systemOrange
            : UIColor(red: 0.72, green: 0.28, blue: 0.0, alpha: 1)
    })

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("RydAR")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Self.accent)
                Text(headline)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 8)
            Text(compact)
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(alerting ? Self.warning : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .activityBackgroundTint(alerting ? Color.orange.opacity(0.28) : nil)
    }
}
