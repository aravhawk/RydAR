import CoreLocation
import Foundation
import MapKit

enum RouteState: Equatable {
    case onRoute
    /// The car left the route, or has not reached it. Every curve ahead is eligible again.
    case offRoute
}

extension Geo {
    /// Shortest distance from a point to a line made of points. A single point is a point.
    static func distanceToPolyline(latitude: Double, longitude: Double, points: [MapPoint]) -> Double {
        guard let first = points.first else { return .greatestFiniteMagnitude }
        let longitudeScale = metersPerDegreeLongitude(latitude)
        func offset(_ point: MapPoint) -> (east: Double, north: Double) {
            ((point.longitude - longitude) * longitudeScale, (point.latitude - latitude) * metersPerDegreeLatitude)
        }
        guard points.count > 1 else {
            let only = offset(first)
            return hypot(only.east, only.north)
        }
        var best = Double.greatestFiniteMagnitude
        var start = offset(first)
        for index in 1..<points.count {
            let end = offset(points[index])
            let spanEast = end.east - start.east
            let spanNorth = end.north - start.north
            let lengthSquared = spanEast * spanEast + spanNorth * spanNorth
            var t = 0.0
            if lengthSquared > 1e-6 {
                t = min(1, max(0, (-start.east * spanEast - start.north * spanNorth) / lengthSquared))
            }
            best = min(best, hypot(start.east + spanEast * t, start.north + spanNorth * t))
            start = end
        }
        return best
    }
}

/// A drive the driver planned before leaving. While the car is on it, only curves on that road
/// are warned about, not the side roads and parallel roads it passes.
struct DriveRoute: Equatable {
    /// Identity for change checks. A route is chosen once and never edited, so comparing it
    /// must not walk a polyline of tens of thousands of points.
    let id = UUID()
    let name: String
    let points: [MapPoint]
    let lengthMeters: Double
    let travelSeconds: TimeInterval

    /// Segments bucketed by map cell, so a position only measures against the road near it.
    private let grid: [Int64: [Int32]]
    private let cellStep: Double
    /// Any segment outside the 3×3 cells around a position is at least this far away.
    static let cellGuaranteeMeters = 500.0
    private static let cellDegrees = 0.005

    /// A curve counts as on the route when at least this share of its shape sits within
    /// `DriveRules.routeCurveMeters` of the route line. A side road that only starts at
    /// a junction on the route falls short.
    static let curveShareOnRoute = 0.5

    static func == (lhs: DriveRoute, rhs: DriveRoute) -> Bool { lhs.id == rhs.id }

    init(name: String, points: [MapPoint], lengthMeters: Double? = nil, travelSeconds: TimeInterval = 0) {
        self.name = name
        self.points = points
        self.travelSeconds = travelSeconds
        let midLatitude = points.isEmpty ? 0 : points.map(\.latitude).reduce(0, +) / Double(points.count)
        // Longitude cells shrink toward the poles; keep them as wide as the latitude cells.
        let step = Self.cellDegrees / max(0.2, cos(midLatitude * .pi / 180))
        cellStep = step
        var cells: [Int64: [Int32]] = [:]
        for index in 0..<max(0, points.count - 1) {
            let a = points[index]
            let b = points[index + 1]
            let rows = Self.cell(min(a.latitude, b.latitude), Self.cellDegrees)...Self.cell(max(a.latitude, b.latitude), Self.cellDegrees)
            let columns = Self.cell(min(a.longitude, b.longitude), step)...Self.cell(max(a.longitude, b.longitude), step)
            for row in rows {
                for column in columns {
                    cells[Self.key(row: row, column: column), default: []].append(Int32(index))
                }
            }
        }
        grid = cells
        if let lengthMeters {
            self.lengthMeters = lengthMeters
        } else {
            var total = 0.0
            for (from, to) in zip(points, points.dropFirst()) {
                total += Geo.distanceMeters(
                    fromLat: from.latitude, fromLon: from.longitude,
                    toLat: to.latitude, toLon: to.longitude
                )
            }
            self.lengthMeters = total
        }
    }

    private static func cell(_ degrees: Double, _ step: Double) -> Int64 {
        Int64((degrees / step).rounded(.down))
    }

    private static func key(row: Int64, column: Int64) -> Int64 {
        row &* 1_000_003 &+ column
    }

    /// Distance to the route line. Past `cellGuaranteeMeters` it returns that bound instead of
    /// the true distance, which is all the callers need to know the car is nowhere near.
    func distanceMeters(latitude: Double, longitude: Double) -> Double {
        let row = Self.cell(latitude, Self.cellDegrees)
        let column = Self.cell(longitude, cellStep)
        var seen = Set<Int32>()
        var best = Double.greatestFiniteMagnitude
        for nearRow in (row - 1)...(row + 1) {
            for nearColumn in (column - 1)...(column + 1) {
                for index in grid[Self.key(row: nearRow, column: nearColumn)] ?? [] where seen.insert(index).inserted {
                    let distance = Geo.distanceToPolyline(
                        latitude: latitude,
                        longitude: longitude,
                        points: [points[Int(index)], points[Int(index) + 1]]
                    )
                    best = min(best, distance)
                }
            }
        }
        return min(best, Self.cellGuaranteeMeters)
    }

    func carries(_ curve: Curve) -> Bool {
        let shape = curve.coordinates.isEmpty
            ? [MapPoint(longitude: curve.longitude, latitude: curve.latitude)]
            : curve.coordinates
        var samples = shape
        for (from, to) in zip(shape, shape.dropFirst()) {
            samples.append(MapPoint(
                longitude: (from.longitude + to.longitude) / 2,
                latitude: (from.latitude + to.latitude) / 2
            ))
        }
        let near = samples.filter {
            distanceMeters(latitude: $0.latitude, longitude: $0.longitude) <= DriveRules.routeCurveMeters
        }.count
        return Double(near) / Double(samples.count) >= Self.curveShareOnRoute
    }
}

extension DriveRoute {
    init?(_ route: MKRoute, name: String) {
        let count = route.polyline.pointCount
        guard count >= 2 else { return nil }
        let coordinates = route.polyline.points()
        let points = (0..<count).map { index -> MapPoint in
            let coordinate = coordinates[index].coordinate
            return MapPoint(longitude: coordinate.longitude, latitude: coordinate.latitude)
        }
        self.init(
            name: name,
            points: points,
            lengthMeters: route.distance,
            travelSeconds: route.expectedTravelTime
        )
    }

    var summary: String {
        let miles = lengthMeters / 1609.344
        let distance = miles < 10
            ? String(format: "%.1f mi", miles)
            : String(format: "%.0f mi", miles)
        guard travelSeconds > 0 else { return distance }
        let minutes = Int((travelSeconds / 60).rounded())
        if minutes < 60 { return "\(distance) · \(max(1, minutes)) min" }
        return "\(distance) · \(minutes / 60) hr \(minutes % 60) min"
    }
}

/// Destination search and Apple Maps directions. It only produces a `DriveRoute`;
/// matching and warning stay in `TripMatcher`.
@MainActor
final class RoutePlanner: NSObject, ObservableObject, MKLocalSearchCompleterDelegate, CLLocationManagerDelegate {
    enum Phase: Equatable {
        case idle
        case planning
        case failed(String)
    }

    @Published var query = "" {
        didSet {
            guard query != oldValue else { return }
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                suggestions = []
            }
            completer.queryFragment = query
        }
    }
    @Published private(set) var suggestions: [MKLocalSearchCompletion] = []
    @Published private(set) var route: DriveRoute?
    @Published private(set) var phase = Phase.idle
    /// Counts finished plans, so a screen can close even when the new route equals the old one.
    @Published private(set) var plannedCount = 0

    private let completer = MKLocalSearchCompleter()
    private let locationManager = CLLocationManager()
    private var task: Task<Void, Never>?
    /// Only the newest request may change what the screen shows.
    private var requestID = 0

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
        locationManager.delegate = self
    }

    func prepare() {
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
    }

    func choose(_ completion: MKLocalSearchCompletion) {
        plan { try await MKLocalSearch(request: MKLocalSearch.Request(completion: completion)).start() }
    }

    func chooseTypedQuery() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        plan { try await MKLocalSearch(request: request).start() }
    }

    func clear() {
        task?.cancel()
        requestID += 1
        route = nil
        phase = .idle
        query = ""
        suggestions = []
    }

    private func plan(_ find: @escaping () async throws -> MKLocalSearch.Response) {
        task?.cancel()
        requestID += 1
        let request = requestID
        phase = .planning
        let source = locationManager.location.map { MKMapItem(placemark: MKPlacemark(coordinate: $0.coordinate)) }
            ?? MKMapItem.forCurrentLocation()
        task = Task { [weak self] in
            do {
                guard let destination = try await find().mapItems.first else {
                    self?.fail("No place found.", request: request)
                    return
                }
                let directions = MKDirections.Request()
                directions.source = source
                directions.destination = destination
                directions.transportType = .automobile
                let response = try await MKDirections(request: directions).calculate()
                guard let best = response.routes.first,
                      let drive = DriveRoute(best, name: destination.name ?? "Destination") else {
                    self?.fail("No driving route found.", request: request)
                    return
                }
                self?.finish(drive, request: request)
            } catch {
                self?.fail("Could not plan that route. Check location and your connection.", request: request)
            }
        }
    }

    private func finish(_ drive: DriveRoute, request: Int) {
        guard request == requestID else { return }
        route = drive
        phase = .idle
        plannedCount += 1
    }

    private func fail(_ message: String, request: Int) {
        guard request == requestID else { return }
        route = nil
        phase = .failed(message)
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        Task { @MainActor in self.suggestions = results }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.suggestions = [] }
    }
}
