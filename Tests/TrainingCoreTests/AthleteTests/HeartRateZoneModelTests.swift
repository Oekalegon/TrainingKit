import Foundation
import Testing
@testable import TrainingCore

@Suite("HeartRateZoneModel")
struct HeartRateZoneModelTests {
    let resting = 50.0
    let max = 190.0

    @Test("karvonen zone 3 midpoint matches the %HRR table")
    func karvonenZoneMidpoint() {
        let model = HeartRateZoneModel(restingHeartRateBPM: resting, maxHeartRateBPM: max, method: .karvonen)
        #expect(model.zoneMidpointRatio(3) == 0.75) // (0.70 + 0.80) / 2
    }

    @Test("percentage-of-max zone boundaries are expressed relative to max, then converted to HRR ratio")
    func percentageOfMaxZoneBoundaries() {
        let model = HeartRateZoneModel(restingHeartRateBPM: resting, maxHeartRateBPM: max, method: .percentageOfMaxHeartRate)

        // Zone 1 is 50%-60% of max HR: 95...114 bpm.
        let range = model.zoneRatioRange(1)!
        let expectedLow = model.deltaHRRatio(for: 0.50 * max)
        let expectedHigh = model.deltaHRRatio(for: 0.60 * max)
        #expect(abs(range.lowerBound - expectedLow) < 1e-9)
        #expect(abs(range.upperBound - expectedHigh) < 1e-9)
    }

    @Test("percentage-of-max boundaries don't depend on resting heart rate")
    func percentageOfMaxIgnoresResting() {
        let low = HeartRateZoneModel(restingHeartRateBPM: 40, maxHeartRateBPM: max, method: .percentageOfMaxHeartRate)
        let high = HeartRateZoneModel(restingHeartRateBPM: 65, maxHeartRateBPM: max, method: .percentageOfMaxHeartRate)

        // The underlying bpm boundary (60% of max) is identical regardless of resting HR...
        let lowBPMBoundary = 0.60 * max
        // ...even though the resulting HRR ratio differs because resting HR differs.
        #expect(low.deltaHRRatio(for: lowBPMBoundary) != high.deltaHRRatio(for: lowBPMBoundary))
        #expect(low.zoneRatioRange(1)!.upperBound == low.deltaHRRatio(for: lowBPMBoundary))
    }

    @Test("lactate-threshold zones scale with the athlete's LTHR")
    func lactateThresholdZonesScaleWithLTHR() {
        let lowLTHR = HeartRateZoneModel(
            restingHeartRateBPM: resting, maxHeartRateBPM: max, lactateThresholdHeartRateBPM: 150, method: .lactateThreshold
        )
        let highLTHR = HeartRateZoneModel(
            restingHeartRateBPM: resting, maxHeartRateBPM: max, lactateThresholdHeartRateBPM: 170, method: .lactateThreshold
        )

        // Zone 4's upper bound is 99% of LTHR; a higher LTHR pushes the bpm (and thus ratio) boundary up.
        #expect(highLTHR.zoneRatioRange(4)!.upperBound > lowLTHR.zoneRatioRange(4)!.upperBound)
    }

    @Test("lactate-threshold method with no LTHR set returns no zone boundaries")
    func lactateThresholdWithoutLTHRReturnsNil() {
        let model = HeartRateZoneModel(restingHeartRateBPM: resting, maxHeartRateBPM: max, method: .lactateThreshold)
        #expect(model.zoneRatioRange(1) == nil)
        #expect(model.zoneMidpointRatio(1) == nil)
    }

    @Test("AthleteProfile.heartRateZoneMethod drives the model built from it")
    func athleteProfileDrivesMethod() {
        let athlete = AthleteProfile(
            restingHeartRateBPM: resting,
            maxHeartRateBPM: max,
            lactateThresholdHeartRateBPM: 160,
            heartRateZoneMethod: .lactateThreshold,
            sex: .male,
            paceModel: PaceModel(thresholdPaceSecondsPerKilometer: 240),
            timeZone: TimeZone(identifier: "UTC")!
        )
        let model = HeartRateZoneModel(athlete: athlete)
        #expect(model.method == .lactateThreshold)
        #expect(model.zoneRatioRange(1) != nil)
    }
}
