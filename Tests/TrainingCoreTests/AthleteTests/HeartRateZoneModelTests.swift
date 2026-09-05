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

    @Test("a model built from the athlete's current settings uses their zone method")
    func modelFromCurrentSettingsUsesMethod() {
        let athlete = AthleteProfile.fixture(lactateThresholdHeartRateBPM: 160, zoneMethod: .lactateThreshold)
        let model = HeartRateZoneModel(settings: athlete.currentHeartRateZoneSettings!)
        #expect(model.method == .lactateThreshold)
        #expect(model.zoneRatioRange(1) != nil)
    }
}

@Suite("AthleteProfile heart-rate zone history")
struct AthleteProfileHeartRateZoneHistoryTests {
    private func date(_ daysFromEpoch: Int) -> Date {
        Date(timeIntervalSince1970: Double(daysFromEpoch) * 86400)
    }

    @Test("looks up the settings effective on a given date, not just the latest")
    func picksSettingsEffectiveOnDate() {
        let old = HeartRateZoneSettings(effectiveDate: date(0), restingHeartRateBPM: 55, maxHeartRateBPM: 185)
        let new = HeartRateZoneSettings(effectiveDate: date(100), restingHeartRateBPM: 48, maxHeartRateBPM: 192)
        let athlete = AthleteProfile(
            sex: .male, paceModel: PaceModel(thresholdPaceSecondsPerKilometer: 240),
            timeZone: TimeZone(identifier: "UTC")!, heartRateZoneHistory: [old, new]
        )

        #expect(athlete.heartRateZoneSettings(asOf: date(50)) == old)
        #expect(athlete.heartRateZoneSettings(asOf: date(150)) == new)
        #expect(athlete.currentHeartRateZoneSettings == new)
    }

    @Test("a date before every recorded entry falls back to the earliest known settings")
    func fallsBackToEarliestForPreHistoryDates() {
        let earliest = HeartRateZoneSettings(effectiveDate: date(100), restingHeartRateBPM: 55, maxHeartRateBPM: 185)
        let athlete = AthleteProfile(
            sex: .male, paceModel: PaceModel(thresholdPaceSecondsPerKilometer: 240),
            timeZone: TimeZone(identifier: "UTC")!, heartRateZoneHistory: [earliest]
        )

        #expect(athlete.heartRateZoneSettings(asOf: date(0)) == earliest)
    }

    @Test("no recorded settings at all returns nil")
    func noSettingsReturnsNil() {
        let athlete = AthleteProfile(
            sex: .male, paceModel: PaceModel(thresholdPaceSecondsPerKilometer: 240),
            timeZone: TimeZone(identifier: "UTC")!, heartRateZoneHistory: []
        )

        #expect(athlete.heartRateZoneSettings(asOf: date(0)) == nil)
        #expect(athlete.currentHeartRateZoneSettings == nil)
    }

    @Test("recomputing an old activity's load uses the settings effective on its date, not today's")
    func loadCalculatorUsesHistoricalSettings() throws {
        let old = HeartRateZoneSettings(effectiveDate: date(0), restingHeartRateBPM: 40, maxHeartRateBPM: 200)
        let new = HeartRateZoneSettings(effectiveDate: date(1000), restingHeartRateBPM: 55, maxHeartRateBPM: 180)
        let athlete = AthleteProfile(
            sex: .male, paceModel: PaceModel(thresholdPaceSecondsPerKilometer: 240),
            timeZone: TimeZone(identifier: "UTC")!, heartRateZoneHistory: [old, new]
        )

        let hr = (0...10).map { HeartRateSample(time: date(10).addingTimeInterval(Double($0) * 60), bpm: 140) }
        let oldActivity = Activity(source: .manual, sport: .running, start: date(10), duration: 600, heartRate: hr)
        let newActivity = Activity(source: .manual, sport: .running, start: date(1010), duration: 600, heartRate: hr)

        let calculator = ExponentialTRIMPCalculator()
        let oldLoad = try calculator.load(for: oldActivity, athlete: athlete)
        let newLoad = try calculator.load(for: newActivity, athlete: athlete)

        // Same raw heart-rate samples, but different resting/max on file for each date, so the
        // resulting ratio — and thus load — should differ.
        #expect(oldLoad.value != newLoad.value)
    }
}
