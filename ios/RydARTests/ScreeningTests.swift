import XCTest
@testable import RydAR

final class ScreeningTests: XCTestCase {
    func testPavedGisLabelsStayPaved() {
        for label in ["paved", "Paved", "p", "paved: asphalt", "paved asphalt", "paved: chip seal", "asphalt", "concrete", "chipnseal"] {
            XCTAssertEqual(roadSurface(from: label), .paved, label)
        }
        for label in ["", "unknown", "Unknown", "unpaved", "u", "unpaved gravel", "gravel", "dirt"] {
            XCTAssertEqual(roadSurface(from: label), .unpaved, label)
        }
    }

    func testPavedRangeMatchesTheBrief() {
        let range = screeningRange(radiusFeet: 200, surface: .paved)
        XCTAssertEqual(range.low, 19.7, accuracy: 0.05)
        XCTAssertEqual(range.high, 22.6, accuracy: 0.05)
    }

    func testTreadQuestionReturnsAfterAboutOneThousandMiles() {
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: TreadStore.choiceKey)
        let meters = defaults.object(forKey: TreadStore.metersKey)
        defer {
            if let previous { defaults.set(previous, forKey: TreadStore.choiceKey) }
            else { defaults.removeObject(forKey: TreadStore.choiceKey) }
            if let meters { defaults.set(meters, forKey: TreadStore.metersKey) }
            else { defaults.removeObject(forKey: TreadStore.metersKey) }
        }
        TreadStore.save(.half)
        TreadStore.addMeters(200)
        XCTAssertEqual(TreadStore.choice, .half)
        let steps = Int((TreadStore.reviewMeters / 200).rounded(.up))
        for _ in 0..<steps { TreadStore.addMeters(200) }
        XCTAssertNil(TreadStore.choice)
    }

    func testWornTreadLowersTheRangeAndNewTreadDoesNot() {
        let design = screeningRange(radiusFeet: 200, surface: .paved)
        let fresh = screeningRange(radiusFeet: 200, surface: .paved, tread: .fresh)
        let low = screeningRange(radiusFeet: 200, surface: .paved, tread: .low)
        let bars = screeningRange(radiusFeet: 200, surface: .paved, tread: .bars)
        XCTAssertEqual(fresh.low, design.low, accuracy: 0.01)
        XCTAssertLessThan(low.low, design.low)
        XCTAssertLessThan(bars.low, low.low)
        XCTAssertEqual(screeningFriction(surface: .paved, tread: .unsure), 0.15, accuracy: 0.001)
        XCTAssertEqual(screeningFriction(surface: .unpaved, tread: .bars), 0.07, accuracy: 0.001)
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

    func testContextKeyUsesSurfaceRadiusAndNight() {
        XCTAssertEqual(radiusBand(feet: 149), "under-150")
        XCTAssertEqual(radiusBand(feet: 150), "150-300")
        XCTAssertEqual(radiusBand(feet: 300), "300-600")
        XCTAssertTrue(isNightHour(19))
        XCTAssertTrue(isNightHour(5))
        XCTAssertFalse(isNightHour(6))
        XCTAssertEqual(
            approachContextKey(surface: .unpaved, radiusFeet: 120, hour: 21),
            "unpaved|under-150|night"
        )
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

    func testBrakingOnsetMovesTheWarningByHowLateItWas() {
        let calm = ApproachMemory(latePasses: 0, earlyPasses: 0)
        let none = VisionCaution(standingWaterOrSnow: false, severeUnevenOnPaved: false)
        let base = baseLookAheadMeters(speedMps: 20)
        XCTAssertEqual(base, 140, accuracy: 0.001)
        let lateBrakes = OnsetMemory(count: 3, sumMeters: 40 * 3)
        let typical = lateBrakes.typicalMeters(baseMeters: base)
        XCTAssertEqual(typical, (120 + 2 * base) / 5, accuracy: 0.001)
        XCTAssertEqual(
            lookAheadMeters(speedMps: 20, memory: calm, vision: none, curveOnset: lateBrakes),
            base + (base - typical),
            accuracy: 0.001
        )
        let onTime = OnsetMemory(count: 3, sumMeters: base * 3)
        XCTAssertEqual(
            lookAheadMeters(speedMps: 20, memory: calm, vision: none, curveOnset: onTime),
            base,
            accuracy: 0.001
        )
        let two = OnsetMemory(count: 2, sumMeters: 40 * 2)
        XCTAssertEqual(
            lookAheadMeters(speedMps: 20, memory: calm, vision: none, curveOnset: two),
            base,
            accuracy: 0.001
        )
        let range = screeningRange(radiusFeet: 120, surface: .unpaved)
        XCTAssertEqual(screeningRange(radiusFeet: 120, surface: .unpaved).low, range.low, accuracy: 0.001)
    }

    func testAKnownRoadOverridesALateSituation() {
        let lateSituation = ApproachMemory(latePasses: 3, earlyPasses: 0)
        let none = VisionCaution(standingWaterOrSnow: false, severeUnevenOnPaved: false)
        let base = baseLookAheadMeters(speedMps: 20)
        let onTimeHere = OnsetMemory(count: 3, sumMeters: base * 3)
        XCTAssertEqual(
            lookAheadMeters(speedMps: 20, memory: lateSituation, vision: none, curveOnset: onTimeHere),
            base,
            accuracy: 0.001
        )
        XCTAssertEqual(
            lookAheadMeters(speedMps: 20, memory: lateSituation, vision: none),
            base * 1.4,
            accuracy: 0.001
        )
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
