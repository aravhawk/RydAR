import SwiftUI

@main
struct CurveAuditApp: App {
    private let session: LiveTripSession

    init() {
        do {
            let curves = try SQLiteCurveStore.openBundled()
            let engine = try TripEngine.bundled()
            let bridge = TripScreenBridge()
            session = LiveTripSession(engine: engine, bridge: bridge, curves: curves)
        } catch {
            fatalError("The bundled curve file could not be opened: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(store: session.curves, trip: session.bridge)
        }
    }
}
