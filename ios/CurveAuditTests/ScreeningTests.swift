import XCTest
@testable import CurveAudit

final class ScreeningTests: XCTestCase {
    func testPavedRangeMatchesTheBrief() {
        let range = screeningRange(radiusFeet: 200, surface: .paved)
        XCTAssertEqual(range.low, 19.7, accuracy: 0.05)
        XCTAssertEqual(range.high, 22.6, accuracy: 0.05)
    }

    func testUnpavedLowEnd() {
        let range = screeningRange(radiusFeet: 200, surface: .unpaved)
        XCTAssertEqual(range.low, 15.5, accuracy: 0.05)
        XCTAssertEqual(range.high, 19.0, accuracy: 0.05)
    }

    func testSpeakUsesTheLowEnd() {
        let range = screeningRange(radiusFeet: 200, surface: .paved)
        XCTAssertFalse(shouldSpeak(effectiveSpeed: range.low, range: range))
        XCTAssertTrue(shouldSpeak(effectiveSpeed: range.low + 0.1, range: range))
        XCTAssertTrue(shouldSpeak(effectiveSpeed: range.high + 1, range: range))
    }

    func testEffectiveSpeedSubtractsAccuracyInMetersPerSecond() {
        let mph = effectiveSpeedMPH(speedMps: 10, accuracyMps: 1)
        XCTAssertEqual(mph, 9 * 2.23694, accuracy: 0.001)
    }

    func testUnder18DriverIsSilent() {
        XCTAssertFalse(allowsInDriveSound(.under18))
        XCTAssertTrue(allowsInDriveSound(.adult))
        XCTAssertTrue(allowsInDriveSound(.passenger))
    }

    func testCameraCanOnlyLower() {
        let confident = CameraEvidence(
            label: .unpaved,
            confidence: 0.9,
            age: 0.2,
            onMatchedRoadROI: true,
            persistent: true
        )
        let lowered = fuseSurface(fileLabel: .paved, camera: confident, threshold: 0.8)
        XCTAssertEqual(lowered.0, .unpaved)
        XCTAssertEqual(lowered.1, .cameraLowered)

        let conflict = CameraEvidence(
            label: .paved,
            confidence: 0.9,
            age: 0.2,
            onMatchedRoadROI: true,
            persistent: true
        )
        let kept = fuseSurface(fileLabel: .unpaved, camera: conflict, threshold: 0.8)
        XCTAssertEqual(kept.0, .unpaved)
        XCTAssertEqual(kept.1, .conflictKeptUnpaved)
    }

    func testSpokenLineMatchesTheContract() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("fixtures/trace.expect.json")
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["spoken_line"] as? String, spokenWarning)
    }
}
