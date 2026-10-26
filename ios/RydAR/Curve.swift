import Foundation

struct MapPoint: Equatable {
    var longitude: Double
    var latitude: Double
}

struct Curve: Identifiable, Equatable {
    var id: String
    var county: String
    var roadName: String
    var surface: RoadSurface
    var radiusFeet: Double
    var deflectionDegrees: Double
    var qualityFlags: String
    var roadClass: String
    /// `rd_design` from the curve file. Empty when a caller does not know it.
    var roadDesign: String = ""
    var closedLoop: Bool
    var latitude: Double
    var longitude: Double
    var minLatitude: Double
    var maxLatitude: Double
    var minLongitude: Double
    var maxLongitude: Double
    var coordinates: [MapPoint]
}

struct CurveCounty: Equatable, Identifiable {
    var name: String
    var minLatitude: Double
    var maxLatitude: Double
    var minLongitude: Double
    var maxLongitude: Double
    var count: Int
    var id: String { name }
}

protocol CurveStore {
    func curves(nearLatitude latitude: Double, longitude: Double, radiusMeters: Double) -> [Curve]
    func curves(minLatitude: Double, maxLatitude: Double, minLongitude: Double, maxLongitude: Double, limit: Int, includeCoordinates: Bool) -> [Curve]
    func counties() -> [CurveCounty]
    func searchRoads(_ query: String, limit: Int) -> [Curve]
    func curve(id: String) -> Curve?
}

extension CurveStore {
    func curves(minLatitude: Double, maxLatitude: Double, minLongitude: Double, maxLongitude: Double, limit: Int, includeCoordinates: Bool) -> [Curve] { [] }
    func counties() -> [CurveCounty] { [] }
    func searchRoads(_ query: String, limit: Int) -> [Curve] { [] }
    func curve(id: String) -> Curve? { nil }
}
