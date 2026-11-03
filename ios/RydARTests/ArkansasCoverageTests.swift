import CoreLocation
import XCTest
@testable import RydAR

final class ArkansasCoverageTests: XCTestCase {
    private var coverage: ArkansasCoverage!

    override func setUpWithError() throws {
        coverage = try XCTUnwrap(ArkansasCoverage.bundled, "ArkansasCounties.json ships in the app")
    }

    func testBundledOutlineHasEveryCounty() {
        XCTAssertEqual(coverage.rings.count, 75)
    }

    func testArkansasTownsAreCovered() {
        XCTAssertTrue(coverage.covers(latitude: 34.7465, longitude: -92.2896), "Little Rock")
        XCTAssertTrue(coverage.covers(latitude: 36.0626, longitude: -94.1574), "Fayetteville")
        XCTAssertTrue(coverage.covers(latitude: 36.4012, longitude: -93.7380), "Eureka Springs")
        XCTAssertTrue(coverage.covers(latitude: 33.3290, longitude: -91.2818), "Lake Village")
        XCTAssertTrue(coverage.covers(latitude: 33.4418, longitude: -94.0377), "Texarkana, AR")
    }

    func testOtherStatesAreNotCovered() {
        XCTAssertFalse(coverage.covers(latitude: 32.7767, longitude: -96.7970), "Dallas")
        XCTAssertFalse(coverage.covers(latitude: 35.0424, longitude: -89.9767), "Memphis airport")
        XCTAssertFalse(coverage.covers(latitude: 36.1540, longitude: -95.9928), "Tulsa")
        XCTAssertFalse(coverage.covers(latitude: 37.3230, longitude: -122.0322), "Cupertino")
        XCTAssertFalse(coverage.covers(latitude: 32.5093, longitude: -92.1193), "Monroe, LA")
    }

    func testTheStartMarginLetsATripBeginRightAtTheLine() {
        // Texarkana, TX is about 400 m from the line.
        XCTAssertFalse(coverage.covers(latitude: 33.4251, longitude: -94.0477))
        XCTAssertTrue(coverage.covers(latitude: 33.4251, longitude: -94.0477,
                                      marginMeters: ArkansasCoverage.startMarginMeters))
        // Poteau, OK is about 16 km out.
        XCTAssertFalse(coverage.covers(latitude: 35.0537, longitude: -94.6235,
                                       marginMeters: ArkansasCoverage.startMarginMeters))
    }

    func testNonFinitePositionsAreNotCovered() {
        XCTAssertFalse(coverage.covers(latitude: .nan, longitude: -92.29))
        XCTAssertFalse(coverage.covers(latitude: 34.74, longitude: .infinity, marginMeters: 5_000))
    }

    func testReadinessNeedsLocationThenPreciseThenArkansas() {
        func check(_ status: CLAuthorizationStatus, _ accuracy: CLAccuracyAuthorization,
                   _ fix: (Double, Double)?) -> TripReadiness {
            TripReadiness.evaluate(authorization: status, accuracy: accuracy,
                                   latitude: fix?.0, longitude: fix?.1, coverage: coverage)
        }
        XCTAssertEqual(check(.notDetermined, .fullAccuracy, nil), .needsPermission)
        XCTAssertEqual(check(.denied, .fullAccuracy, (34.74, -92.29)), .locationOff)
        XCTAssertEqual(check(.restricted, .fullAccuracy, nil), .locationOff)
        XCTAssertEqual(check(.authorizedWhenInUse, .reducedAccuracy, (34.74, -92.29)), .needsPrecise)
        XCTAssertEqual(check(.authorizedWhenInUse, .fullAccuracy, nil), .locating)
        XCTAssertEqual(check(.authorizedWhenInUse, .fullAccuracy, (37.32, -122.03)), .outsideArkansas)
        XCTAssertEqual(check(.authorizedWhenInUse, .fullAccuracy, (34.74, -92.29)), .ready)
        XCTAssertEqual(check(.authorizedAlways, .fullAccuracy, (34.74, -92.29)), .ready)
        XCTAssertTrue(TripReadiness.ready.canStart)
        XCTAssertFalse(TripReadiness.outsideArkansas.canStart)
        XCTAssertEqual(TripReadiness.outsideArkansas.explanation,
                       "RydAR covers Arkansas roads. More states are coming soon.")
    }

    func testDriveReadoutSaysOutsideArkansasWithoutACurve() {
        let readout = driveReadout(hasCurve: false, roadName: nil, gpsStatus: "GPS ready",
                                   measuredSpeedMPH: 55, placeTitle: nil, placeDetail: nil,
                                   outsideArkansas: true)
        XCTAssertEqual(readout.headline, "Outside Arkansas")
        XCTAssertEqual(readout.locationPin, "No curve data")
        let inside = driveReadout(hasCurve: false, roadName: nil, gpsStatus: "GPS ready",
                                  measuredSpeedMPH: 55, placeTitle: nil, placeDetail: nil)
        XCTAssertEqual(inside.headline, "No curve ahead")
    }
}
