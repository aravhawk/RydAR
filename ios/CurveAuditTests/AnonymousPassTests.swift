import XCTest
@testable import CurveAudit

final class AnonymousPassTests: XCTestCase {
    func testSpeedBandFloorsToFiveAndClamps() {
        XCTAssertEqual(AnonymousPass.speedBand(22.9), 20)
        XCTAssertEqual(AnonymousPass.speedBand(25), 25)
        XCTAssertEqual(AnonymousPass.speedBand(-4), 0)
        XCTAssertEqual(AnonymousPass.speedBand(180), 150)
        XCTAssertEqual(AnonymousPass.speedBand(.nan), 0)
    }

    func testBodyMatchesThePassContract() {
        let body = AnonymousPass.body(from: sample(id: "007-2-3", speed: 44.7, hour: 14), appVersion: "0.1.0")
        XCTAssertEqual(body?.curve_id, "007-2-3")
        XCTAssertEqual(body?.direction, "N")
        XCTAssertEqual(body?.speed_band_mph, 40)
        XCTAssertEqual(body?.hour_bucket, 14)
        XCTAssertEqual(body?.app_version, "0.1.0")
        XCTAssertNil(body?.lat_accel_band)
        XCTAssertNil(AnonymousPass.body(from: sample(id: "preview-curve", speed: 20, hour: 14), appVersion: "0.1.0"))
        XCTAssertNil(AnonymousPass.body(from: sample(id: "143-9-1", speed: 20, hour: 14), appVersion: " "))
        XCTAssertNil(AnonymousPass.body(from: sample(id: "143-9-1", speed: 20, hour: 24), appVersion: "0.1.0"))
        XCTAssertNotNil(AnonymousPass.body(from: sample(id: "119-4-8", speed: 30, hour: 9), appVersion: "0.1.0"))
        XCTAssertNil(AnonymousPass.body(from: sample(id: "002-1-1", speed: 30, hour: 9), appVersion: "0.1.0"))
    }

    private func sample(id: String, speed: Double, hour: Int) -> CompletedPass {
        CompletedPass(
            curveID: id,
            direction: "N",
            effectiveSpeedMPH: speed,
            vLoMPH: 19,
            vHiMPH: 23,
            spoke: true,
            hourBucket: hour,
            late: false,
            surfaceUsed: .paved,
            radiusBand: "150-300",
            lookAheadMeters: 140,
            contextKey: "paved|150-300|day"
        )
    }
}
