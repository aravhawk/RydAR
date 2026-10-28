import CoreLocation
import Foundation

/// Where the rider is, split so the drive screen can show it once as the headline
/// and once more only when the second line adds a street or a town.
struct RiderPlace: Equatable {
    var title: String
    var detail: String
}

struct PlaceParts: Equatable {
    var name: String? = nil
    var thoroughfare: String? = nil
    var subLocality: String? = nil
    var locality: String? = nil
    var administrativeArea: String? = nil
}

protocol PlaceGeocoding: AnyObject {
    func cancel()
    func reverse(latitude: Double, longitude: Double, completion: @escaping (PlaceParts?) -> Void)
}

/// Turns a coordinate into a street and town, and keeps the last result while the phone has not moved.
final class RiderPlaceLookup {
    static let reuseMeters = 80.0

    private let geocoder: PlaceGeocoding
    private var generation = 0
    private var pending: (latitude: Double, longitude: Double)?
    private var failed: (latitude: Double, longitude: Double)?
    private var resolved: (place: RiderPlace, latitude: Double, longitude: Double)?

    init(geocoder: PlaceGeocoding = CoreLocationPlaceGeocoder()) {
        self.geocoder = geocoder
    }

    /// The best name already known for this coordinate. A fresh stop starts as the coordinate itself.
    func immediate(latitude: Double, longitude: Double) -> RiderPlace {
        if let resolved, Self.isClose(resolved.latitude, resolved.longitude, latitude, longitude) {
            return resolved.place
        }
        return coordinatePlace(latitude: latitude, longitude: longitude)
    }

    /// Asks for a street and town. Calls `update` only when a new name arrives.
    func resolve(latitude: Double, longitude: Double, update: @escaping () -> Void) {
        let run = { self.resolveOnMain(latitude: latitude, longitude: longitude, update: update) }
        if Thread.isMainThread {
            run()
        } else {
            DispatchQueue.main.async(execute: run)
        }
    }

    private func resolveOnMain(latitude: Double, longitude: Double, update: @escaping () -> Void) {
        if let resolved, Self.isClose(resolved.latitude, resolved.longitude, latitude, longitude) {
            return
        }
        if let pending, Self.isClose(pending.latitude, pending.longitude, latitude, longitude) {
            return
        }
        if let failed, Self.isClose(failed.latitude, failed.longitude, latitude, longitude) {
            return
        }
        generation += 1
        let token = generation
        pending = (latitude, longitude)
        geocoder.cancel()
        geocoder.reverse(latitude: latitude, longitude: longitude) { [weak self] parts in
            guard let self, token == self.generation else { return }
            self.pending = nil
            guard let parts else {
                self.failed = (latitude, longitude)
                return
            }
            self.failed = nil
            self.resolved = (
                riderPlace(from: parts, latitude: latitude, longitude: longitude),
                latitude,
                longitude
            )
            update()
        }
    }

    private static func isClose(_ fromLat: Double, _ fromLon: Double, _ toLat: Double, _ toLon: Double) -> Bool {
        Geo.distanceMeters(fromLat: fromLat, fromLon: fromLon, toLat: toLat, toLon: toLon) <= reuseMeters
    }
}

final class CoreLocationPlaceGeocoder: PlaceGeocoding {
    private let geocoder = CLGeocoder()

    func cancel() {
        geocoder.cancelGeocode()
    }

    func reverse(latitude: Double, longitude: Double, completion: @escaping (PlaceParts?) -> Void) {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        geocoder.reverseGeocodeLocation(location) { marks, _ in
            completion(marks?.first.map { mark in
                PlaceParts(
                    name: mark.name,
                    thoroughfare: mark.thoroughfare,
                    subLocality: mark.subLocality,
                    locality: mark.locality,
                    administrativeArea: mark.administrativeArea
                )
            })
        }
    }
}

func coordinateText(latitude: Double, longitude: Double) -> String {
    let locale = Locale(identifier: "en_US_POSIX")
    let lat = String(format: "%.4f", locale: locale, abs(latitude))
    let lon = String(format: "%.4f", locale: locale, abs(longitude))
    let latHemisphere = latitude >= 0 ? "N" : "S"
    let lonHemisphere = longitude >= 0 ? "E" : "W"
    return "\(lat)° \(latHemisphere), \(lon)° \(lonHemisphere)"
}

func coordinatePlace(latitude: Double, longitude: Double) -> RiderPlace {
    let text = coordinateText(latitude: latitude, longitude: longitude)
    return RiderPlace(title: text, detail: text)
}

/// Most specific line first: a named place, then the street, then the town.
/// The detail is everything after the title, or the coordinate when the title is only a town.
func riderPlace(from parts: PlaceParts, latitude: Double, longitude: Double) -> RiderPlace {
    let coordinate = coordinateText(latitude: latitude, longitude: longitude)
    let street = cleaned(parts.thoroughfare)
    let named = cleaned(parts.name)
    let neighborhood = cleaned(parts.subLocality)
    let city = cleaned(parts.locality)
    let region = cleaned(parts.administrativeArea)
    let town = [city, region].compactMap { $0 }.joined(separator: ", ")
    let poi: String? = {
        guard let named else { return nil }
        if named == street || named == city || named == town || named == neighborhood { return nil }
        return named
    }()

    var lines: [String] = []
    if let poi { lines.append(poi) }
    if let street { lines.append(street) }
    if let neighborhood, neighborhood != city, neighborhood != street { lines.append(neighborhood) }
    if !town.isEmpty { lines.append(town) }
    var seen = Set<String>()
    lines = lines.filter { seen.insert($0).inserted }

    let title = lines.first ?? coordinate
    let remainder = lines.dropFirst().joined(separator: ", ")
    let detail = remainder.isEmpty ? coordinate : remainder
    return RiderPlace(title: title, detail: detail)
}

private func cleaned(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
        return nil
    }
    return trimmed
}

/// Words for the curve line, the speed, and the location pin.
/// A stop shows the place. The same words are not printed again on the pin.
struct DriveReadout: Equatable {
    var headline: String
    var locationPin: String?
    var speedMPH: Double?
}

func driveReadout(
    hasCurve: Bool,
    roadName: String?,
    gpsStatus: String,
    measuredSpeedMPH: Double?,
    placeTitle: String?,
    placeDetail: String?
) -> DriveReadout {
    let standingStill = gpsStatus == "Standing still"
    let title = standingStill ? nonempty(placeTitle) : nil
    let detail = standingStill ? nonempty(placeDetail) : nil
    let road = nonempty(roadName)

    let headline: String
    if hasCurve {
        headline = road ?? "Curve ahead"
    } else if let title {
        headline = title
    } else if gpsStatus == "GPS ready" {
        headline = "No curve ahead"
    } else {
        headline = gpsStatus
    }

    let pin: String?
    if standingStill {
        if let detail, detail != headline {
            pin = detail
        } else {
            pin = nil
        }
    } else {
        pin = gpsStatus
    }

    return DriveReadout(headline: headline, locationPin: pin, speedMPH: measuredSpeedMPH)
}

private func nonempty(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
        return nil
    }
    return trimmed
}
