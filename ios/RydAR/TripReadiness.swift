import CoreLocation
import Foundation

/// Whether a trip can start from here. A trip needs location, Precise Location, and a fix in
/// (or right at the edge of) Arkansas, because the curve data only covers Arkansas roads.
/// The map and Settings never depend on this.
enum TripReadiness: Equatable {
    case needsPermission
    case locationOff
    case needsPrecise
    case locating
    case outsideArkansas
    case ready

    static func evaluate(
        authorization: CLAuthorizationStatus,
        accuracy: CLAccuracyAuthorization,
        latitude: Double?,
        longitude: Double?,
        coverage: ArkansasCoverage?
    ) -> TripReadiness {
        switch authorization {
        case .notDetermined:
            return .needsPermission
        case .denied, .restricted:
            return .locationOff
        default:
            break
        }
        if accuracy == .reducedAccuracy { return .needsPrecise }
        guard let latitude, let longitude else { return .locating }
        // Without the bundled outline there is nothing to check against. Do not block on our own file.
        guard let coverage else { return .ready }
        return coverage.covers(
            latitude: latitude,
            longitude: longitude,
            marginMeters: ArkansasCoverage.startMarginMeters
        ) ? .ready : .outsideArkansas
    }

    var canStart: Bool { self == .ready }

    /// One line under the parked header. Empty when a trip can start.
    var explanation: String {
        switch self {
        case .needsPermission, .locationOff:
            return "Trips need your location to find the curves ahead."
        case .needsPrecise:
            return "Trips need Precise Location to match the curve you're approaching."
        case .locating:
            return "Finding your location…"
        case .outsideArkansas:
            return "RydAR covers Arkansas roads. More states are coming soon."
        case .ready:
            return ""
        }
    }
}

/// One coarse fix on the parked screen, enough to tell Arkansas from elsewhere.
/// The trip engine owns location once a drive starts.
@MainActor
final class TripReadinessMonitor: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var readiness: TripReadiness = .locating
    private let manager = CLLocationManager()
    private var fix: CLLocation?
    /// A fix older than this may be from before a drive out of state.
    private static let freshSeconds: TimeInterval = 120
    private static let usableAccuracyMeters: CLLocationAccuracy = 1_000

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 250
        evaluate()
    }

    /// Re-reads permission and asks for a fresh fix. Call when the screen appears or the app returns.
    func refresh() {
        if let cached = manager.location, Self.usable(cached) { fix = cached }
        evaluate()
        if isAuthorized { manager.startUpdatingLocation() }
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    private var isAuthorized: Bool {
        let status = manager.authorizationStatus
        return status == .authorizedWhenInUse || status == .authorizedAlways
    }

    private func evaluate() {
        if let fix, !Self.usable(fix) { self.fix = nil }
        readiness = TripReadiness.evaluate(
            authorization: manager.authorizationStatus,
            accuracy: manager.accuracyAuthorization,
            latitude: fix?.coordinate.latitude,
            longitude: fix?.coordinate.longitude,
            coverage: ArkansasCoverage.bundled
        )
    }

    private static func usable(_ location: CLLocation) -> Bool {
        location.horizontalAccuracy >= 0
            && location.horizontalAccuracy <= usableAccuracyMeters
            && abs(location.timestamp.timeIntervalSinceNow) <= freshSeconds
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.refresh() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            guard Self.usable(location) else { return }
            self.fix = location
            self.evaluate()
            // One good fix is enough on the parked screen. Refresh asks again later.
            if location.horizontalAccuracy <= 100 { self.manager.stopUpdatingLocation() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.evaluate() }
    }
}
