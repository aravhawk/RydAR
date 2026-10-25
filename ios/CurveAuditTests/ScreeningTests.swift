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

    func testLookAheadNeverShrinksAndCapsAt450() {
        let calm = ApproachMemory(latePasses: 0, earlyPasses: 0)
        let none = VisionCaution(standingWaterOrSnow: false, severeUnevenOnPaved: false)
        let base = baseLookAheadMeters(speedMps: 20)
        XCTAssertEqual(lookAheadMeters(speedMps: 20, memory: calm, vision: none), base, accuracy: 0.001)

        let late = ApproachMemory(latePasses: 3, earlyPasses: 0)
        let earlier = lookAheadMeters(speedMps: 20, memory: late, vision: none)
        XCTAssertGreaterThan(earlier, base)
        XCTAssertLessThanOrEqual(earlier, 450)

        let alreadyFar = lookAheadMeters(speedMps: 80, memory: late, vision: VisionCaution(standingWaterOrSnow: true, severeUnevenOnPaved: true))
        XCTAssertEqual(alreadyFar, 450, accuracy: 0.001)
    }

    func testOneLatePassDoesNotMoveTheWarning() {
        let one = ApproachMemory(latePasses: 1, earlyPasses: 0)
        let none = VisionCaution(standingWaterOrSnow: false, severeUnevenOnPaved: false)
        XCTAssertEqual(
            lookAheadMeters(speedMps: 15, memory: one, vision: none),
            baseLookAheadMeters(speedMps: 15),
            accuracy: 0.001
        )
    }

    func testWaterMovesTheWarningEarlierWithoutAHabit() {
        let calm = ApproachMemory(latePasses: 0, earlyPasses: 0)
        let water = VisionCaution(standingWaterOrSnow: true, severeUnevenOnPaved: false)
        let base = baseLookAheadMeters(speedMps: 15)
        XCTAssertEqual(lookAheadMeters(speedMps: 15, memory: calm, vision: water), base * 1.3, accuracy: 0.001)
    }

    func testRepeatPromptStaysOffUntilThisPassIsOverRange() {
        let range = screeningRange(radiusFeet: 200, surface: .paved)
        XCTAssertTrue(suppressRepeatPrompt(passesUnderRange: 3, effectiveSpeed: range.low, range: range))
        XCTAssertFalse(suppressRepeatPrompt(passesUnderRange: 3, effectiveSpeed: range.low + 0.1, range: range))
        XCTAssertFalse(suppressRepeatPrompt(passesUnderRange: 2, effectiveSpeed: range.low, range: range))
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
