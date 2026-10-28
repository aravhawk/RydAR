import SwiftUI

@main
struct RydARApp: App {
    /// Nil when the bundled curve file or the trip log cannot be opened. The app then says so
    /// instead of showing roads it does not have.
    private let session: LiveTripSession?
    private let startupFailure: String?

    init() {
        do {
            let curves = try SQLiteCurveStore.openBundled()
            let engine = try TripEngine.bundled()
            let bridge = TripScreenBridge()
            session = LiveTripSession(engine: engine, bridge: bridge, curves: curves)
            startupFailure = nil
        } catch {
            session = nil
            startupFailure = "\(error)"
        }
    }

    var body: some Scene {
        WindowGroup {
            if let session {
                ContentView(store: session.curves, trip: session.bridge)
            } else {
                StartupFailureView(detail: startupFailure ?? "")
            }
        }
    }
}

/// Shown when the app cannot open its own data. Nothing here records or warns.
private struct StartupFailureView: View {
    var detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(RydarTheme.warningText)
            Text("RydAR can't open its curve data.")
                .font(.title.bold())
            Text("Quit and reopen the app. If it keeps happening, reinstall it. Nothing is being recorded and no warnings will play.")
                .foregroundStyle(.secondary)
            if !detail.isEmpty {
                Text(detail)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
