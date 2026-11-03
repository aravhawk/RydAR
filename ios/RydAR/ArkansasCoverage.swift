import Foundation

/// Where RydAR has road data: the 75 Arkansas counties, read from the bundled
/// `ArkansasCounties.json`. Checked on the phone. No location leaves the device for this.
///
/// The county outlines are simplified to about 100 m, so the edges carry a margin:
/// a trip may start within `startMarginMeters` of the state line, and the drive screen
/// only says "Outside Arkansas" once the car is `outsideMarginMeters` past it.
struct ArkansasCoverage {
    static let startMarginMeters = 2_000.0
    static let outsideMarginMeters = 1_000.0

    /// One closed ring per county, as (longitude, latitude) points.
    let rings: [[MapPoint]]
    private let minLatitude: Double
    private let maxLatitude: Double
    private let minLongitude: Double
    private let maxLongitude: Double

    init(rings: [[MapPoint]]) {
        self.rings = rings.filter { $0.count >= 3 }
        let points = self.rings.flatMap { $0 }
        minLatitude = points.map(\.latitude).min() ?? 0
        maxLatitude = points.map(\.latitude).max() ?? 0
        minLongitude = points.map(\.longitude).min() ?? 0
        maxLongitude = points.map(\.longitude).max() ?? 0
    }

    /// Loaded once. Nil only if the bundled file is missing or unreadable.
    static let bundled: ArkansasCoverage? = {
        guard let url = Bundle.main.url(forResource: "ArkansasCounties", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }()

    static func decode(_ data: Data) -> ArkansasCoverage? {
        struct File: Decodable { var rings: [[Double]] }
        guard let file = try? JSONDecoder().decode(File.self, from: data) else { return nil }
        let rings = file.rings.map { flat in
            stride(from: 0, to: flat.count - 1, by: 2).map {
                MapPoint(longitude: flat[$0], latitude: flat[$0 + 1])
            }
        }
        let coverage = ArkansasCoverage(rings: rings)
        return coverage.rings.isEmpty ? nil : coverage
    }

    /// Inside a county, or within `marginMeters` of one.
    func covers(latitude: Double, longitude: Double, marginMeters: Double = 0) -> Bool {
        guard latitude.isFinite, longitude.isFinite else { return false }
        let padLatitude = marginMeters / Geo.metersPerDegreeLatitude
        let padLongitude = marginMeters / max(1, Geo.metersPerDegreeLongitude(latitude))
        guard latitude >= minLatitude - padLatitude, latitude <= maxLatitude + padLatitude,
              longitude >= minLongitude - padLongitude, longitude <= maxLongitude + padLongitude else {
            return false
        }
        if rings.contains(where: { Self.ring($0, contains: latitude, longitude) }) { return true }
        guard marginMeters > 0 else { return false }
        return nearestEdgeMeters(latitude: latitude, longitude: longitude) <= marginMeters
    }

    /// Even-odd ray cast. Points exactly on a shared county line count for one side or the other.
    private static func ring(_ ring: [MapPoint], contains latitude: Double, _ longitude: Double) -> Bool {
        var inside = false
        var j = ring.count - 1
        for i in 0..<ring.count {
            let a = ring[i]
            let b = ring[j]
            if (a.latitude > latitude) != (b.latitude > latitude) {
                let crossing = (b.longitude - a.longitude) * (latitude - a.latitude)
                    / (b.latitude - a.latitude) + a.longitude
                if longitude < crossing { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    private func nearestEdgeMeters(latitude: Double, longitude: Double) -> Double {
        let scale = Geo.metersPerDegreeLongitude(latitude)
        var best = Double.greatestFiniteMagnitude
        for ring in rings {
            var previous = ring[ring.count - 1]
            for point in ring {
                let ax = (previous.longitude - longitude) * scale
                let ay = (previous.latitude - latitude) * Geo.metersPerDegreeLatitude
                let bx = (point.longitude - longitude) * scale
                let by = (point.latitude - latitude) * Geo.metersPerDegreeLatitude
                let dx = bx - ax
                let dy = by - ay
                let length = dx * dx + dy * dy
                let t = length > 0 ? min(1, max(0, -(ax * dx + ay * dy) / length)) : 0
                best = min(best, hypot(ax + t * dx, ay + t * dy))
                previous = point
            }
        }
        return best
    }
}
