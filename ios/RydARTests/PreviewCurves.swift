import Foundation
import CoreLocation
@testable import RydAR

/// Five rows copied from the bundled database, for tests that need a small known set of curves.
struct PreviewCurves: CurveStore {
    func curves(nearLatitude latitude: Double, longitude: Double, radiusMeters: Double) -> [Curve] {
        let center = CLLocation(latitude: latitude, longitude: longitude)
        return Self.samples.filter {
            center.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) <= radiusMeters
        }
    }

    static let samples: [Curve] = [
        Curve(id: "007-2-3", county: "Benton", roadName: "N Old Wire Rd",
              surface: .unpaved, radiusFeet: 114.5, deflectionDegrees: 139.2,
              qualityFlags: "", roadClass: "County", closedLoop: false,
              latitude: 36.275376, longitude: -94.117058,
              minLatitude: 36.27487, maxLatitude: 36.275379,
              minLongitude: -94.117497, maxLongitude: -94.116852,
              coordinates: [
                MapPoint(longitude: -94.117462, latitude: 36.27487),
                MapPoint(longitude: -94.11748, latitude: 36.274913),
                MapPoint(longitude: -94.117497, latitude: 36.274955),
                MapPoint(longitude: -94.117497, latitude: 36.275),
                MapPoint(longitude: -94.117495, latitude: 36.275045),
                MapPoint(longitude: -94.117494, latitude: 36.27509),
                MapPoint(longitude: -94.117479, latitude: 36.275133),
                MapPoint(longitude: -94.117455, latitude: 36.275174),
                MapPoint(longitude: -94.117431, latitude: 36.275214),
                MapPoint(longitude: -94.117401, latitude: 36.275251),
                MapPoint(longitude: -94.117358, latitude: 36.27528),
                MapPoint(longitude: -94.117315, latitude: 36.275308),
                MapPoint(longitude: -94.117271, latitude: 36.275335),
                MapPoint(longitude: -94.117219, latitude: 36.275351),
                MapPoint(longitude: -94.117166, latitude: 36.275366),
                MapPoint(longitude: -94.117114, latitude: 36.275379),
                MapPoint(longitude: -94.117058, latitude: 36.275376),
                MapPoint(longitude: -94.117003, latitude: 36.275372),
                MapPoint(longitude: -94.116948, latitude: 36.275367),
                MapPoint(longitude: -94.1169, latitude: 36.275344),
                MapPoint(longitude: -94.116852, latitude: 36.275321),
              ]),
        Curve(id: "007-2-1", county: "Benton", roadName: "N Old Wire Rd",
              surface: .unpaved, radiusFeet: 365.7, deflectionDegrees: 16.9,
              qualityFlags: "", roadClass: "County", closedLoop: false,
              latitude: 36.264707, longitude: -94.118041,
              minLatitude: 36.264632, maxLatitude: 36.264871,
              minLongitude: -94.118101, maxLongitude: -94.117851,
              coordinates: [
                MapPoint(longitude: -94.118101, latitude: 36.264632),
                MapPoint(longitude: -94.118073, latitude: 36.264671),
                MapPoint(longitude: -94.118041, latitude: 36.264707),
                MapPoint(longitude: -94.118004, latitude: 36.264741),
                MapPoint(longitude: -94.117968, latitude: 36.264775),
                MapPoint(longitude: -94.117932, latitude: 36.264809),
                MapPoint(longitude: -94.117891, latitude: 36.26484),
                MapPoint(longitude: -94.117851, latitude: 36.264871),
              ]),
        Curve(id: "007-8008-8409", county: "Benton", roadName: "Brightwater Xing",
              surface: .paved, radiusFeet: 116.4, deflectionDegrees: 47.4,
              qualityFlags: "", roadClass: "County", closedLoop: false,
              latitude: 36.37032, longitude: -94.034778,
              minLatitude: 36.370186, maxLatitude: 36.370468,
              minLongitude: -94.034896, maxLongitude: -94.034769,
              coordinates: [
                MapPoint(longitude: -94.034896, latitude: 36.370468),
                MapPoint(longitude: -94.034859, latitude: 36.370435),
                MapPoint(longitude: -94.034824, latitude: 36.3704),
                MapPoint(longitude: -94.034792, latitude: 36.370363),
                MapPoint(longitude: -94.034778, latitude: 36.37032),
                MapPoint(longitude: -94.034769, latitude: 36.370276),
                MapPoint(longitude: -94.03477, latitude: 36.370231),
                MapPoint(longitude: -94.034775, latitude: 36.370186),
              ]),
        Curve(id: "007-338-1055", county: "Benton", roadName: "Canyon Village Rd",
              surface: .unpaved, radiusFeet: 94.0, deflectionDegrees: 74.8,
              qualityFlags: "", roadClass: "County", closedLoop: false,
              latitude: 36.321035, longitude: -93.986921,
              minLatitude: 36.320949, maxLatitude: 36.321295,
              minLongitude: -93.986993, maxLongitude: -93.986734,
              coordinates: [
                MapPoint(longitude: -93.986989, latitude: 36.321295),
                MapPoint(longitude: -93.986993, latitude: 36.32125),
                MapPoint(longitude: -93.986989, latitude: 36.321205),
                MapPoint(longitude: -93.986981, latitude: 36.32116),
                MapPoint(longitude: -93.986966, latitude: 36.321117),
                MapPoint(longitude: -93.986946, latitude: 36.321075),
                MapPoint(longitude: -93.986921, latitude: 36.321035),
                MapPoint(longitude: -93.986885, latitude: 36.321002),
                MapPoint(longitude: -93.98684, latitude: 36.320976),
                MapPoint(longitude: -93.986787, latitude: 36.320962),
                MapPoint(longitude: -93.986734, latitude: 36.320949),
              ]),
        Curve(id: "143-14437-14971", county: "Washington", roadName: "Grove Dr",
              surface: .unpaved, radiusFeet: 100.1, deflectionDegrees: 67.7,
              qualityFlags: "", roadClass: "County", closedLoop: false,
              latitude: 36.223624, longitude: -94.019884,
              minLatitude: 36.2234, maxLatitude: 36.223803,
              minLongitude: -94.019897, maxLongitude: -94.019636,
              coordinates: [
                MapPoint(longitude: -94.019883, latitude: 36.2234),
                MapPoint(longitude: -94.019892, latitude: 36.223444),
                MapPoint(longitude: -94.019894, latitude: 36.22349),
                MapPoint(longitude: -94.019897, latitude: 36.223535),
                MapPoint(longitude: -94.01989, latitude: 36.223579),
                MapPoint(longitude: -94.019884, latitude: 36.223624),
                MapPoint(longitude: -94.019848, latitude: 36.223659),
                MapPoint(longitude: -94.019812, latitude: 36.223693),
                MapPoint(longitude: -94.019771, latitude: 36.223724),
                MapPoint(longitude: -94.019729, latitude: 36.223753),
                MapPoint(longitude: -94.019684, latitude: 36.223779),
                MapPoint(longitude: -94.019636, latitude: 36.223803),
              ]),
    ]

    func curves(
        minLatitude: Double, maxLatitude: Double, minLongitude: Double, maxLongitude: Double,
        limit: Int, includeCoordinates: Bool = true
    ) -> [Curve] {
        Array(Self.samples.filter {
            $0.maxLatitude >= minLatitude && $0.minLatitude <= maxLatitude
                && $0.maxLongitude >= minLongitude && $0.minLongitude <= maxLongitude
        }.prefix(max(0, limit)))
    }

    func counties() -> [CurveCounty] {
        Dictionary(grouping: Self.samples, by: \.county).map { name, curves in
            CurveCounty(
                name: name,
                minLatitude: curves.map(\.minLatitude).min() ?? 0,
                maxLatitude: curves.map(\.maxLatitude).max() ?? 0,
                minLongitude: curves.map(\.minLongitude).min() ?? 0,
                maxLongitude: curves.map(\.maxLongitude).max() ?? 0,
                count: curves.count
            )
        }.sorted { $0.name < $1.name }
    }

    func searchRoads(_ query: String, limit: Int) -> [Curve] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard needle.count >= 2 else { return [] }
        return Array(Self.samples.filter { $0.roadName.lowercased().contains(needle) }.prefix(max(0, limit)))
    }

    func curve(id: String) -> Curve? {
        Self.samples.first { $0.id == id }
    }
}
