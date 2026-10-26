import SwiftUI

@main
struct RydARApp: App {
    /// Nil when the curve file cannot be opened. The app then runs as the sample-road
    /// preview, which says "Sample roads only" and "Not recording", instead of crashing at launch.
    private let session: LiveTripSession?

    init() {
        do {
            let curves = try SQLiteCurveStore.openBundled()
            let engine = try TripEngine.bundled()
            let bridge = TripScreenBridge()
            session = LiveTripSession(engine: engine, bridge: bridge, curves: curves)
        } catch {
            print("The bundled curve file could not be opened: \(error)")
            session = nil
        }
    }

    var body: some Scene {
        WindowGroup {
            if let session {
                ContentView(store: session.curves, trip: session.bridge)
            } else {
                ContentView()
            }
        }
    }
}
