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

protocol CurveStore {
    func curves(nearLatitude latitude: Double, longitude: Double, radiusMeters: Double) -> [Curve]
}
