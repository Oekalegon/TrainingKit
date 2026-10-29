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

    @Test("karvonen zone bpm ranges convert the ratio table back to bpm via resting/max")
    func karvonenZoneBPMRange() {
        let model = HeartRateZoneModel(restingHeartRateBPM: resting, maxHeartRateBPM: max, method: .karvonen)

        // Zone 1 is 50%-60% HRR: resting + ratio * (max - resting), i.e. 120...134 bpm here.
        let range = model.zoneBPMRange(1)!
        #expect(abs(range.lowerBound - 120) < 1e-9)
        #expect(abs(range.upperBound - 134) < 1e-9)
    }

    @Test("zone bpm ranges round-trip through zoneRatioRange for every method")
    func zoneBPMRangeRoundTripsThroughRatio() {
        for method in [HeartRateZoneMethod.karvonen, .percentageOfMaxHeartRate] {
            let model = HeartRateZoneModel(restingHeartRateBPM: resting, maxHeartRateBPM: max, method: method)
            let ratioRange = model.zoneRatioRange(3)!
            let bpmRange = model.zoneBPMRange(3)!
            #expect(abs(model.deltaHRRatio(for: bpmRange.lowerBound) - ratioRange.lowerBound) < 1e-9)
            #expect(abs(model.deltaHRRatio(for: bpmRange.upperBound) - ratioRange.upperBound) < 1e-9)
        }
    }

    @Test("zone bpm range is nil under the same conditions zoneRatioRange is nil for")
    func zoneBPMRangeNilMatchesRatioRange() {
        let outOfRange = HeartRateZoneModel(restingHeartRateBPM: resting, maxHeartRateBPM: max, method: .karvonen)
        #expect(outOfRange.zoneBPMRange(0) == nil)
        #expect(outOfRange.zoneBPMRange(6) == nil)

        let noLTHR = HeartRateZoneModel(restingHeartRateBPM: resting, maxHeartRateBPM: max, method: .lactateThreshold)
        #expect(noLTHR.zoneBPMRange(1) == nil)
    }

    @Test("a model built from the athlete's current settings uses their zone method")
    func modelFromCurrentSettingsUsesMethod() {
        let athlete = AthleteProfile.fixture(lactateThresholdHeartRateBPM: 160, zoneMethod: .lactateThreshold)
        let model = HeartRateZoneModel(settings: athlete.currentHeartRateZoneSettings!)
        #expect(model.method == .lactateThreshold)
        #expect(model.zoneRatioRange(1) != nil)
    }
}

/// Zone positions (MVP5-148): `n.0` is the bottom of zone `n`, `(n+1).0` its top.
@Suite("HeartRateZoneModel zone positions")
struct HeartRateZonePositionTests {
    private let methods: [HeartRateZoneMethod] = [.karvonen, .percentageOfMaxHeartRate, .lactateThreshold]

    private func model(_ method: HeartRateZoneMethod) -> HeartRateZoneModel {
        HeartRateZoneModel(restingHeartRateBPM: 50, maxHeartRateBPM: 190, lactateThresholdHeartRateBPM: 165, method: method)
    }

    @Test("a whole zone as positions is the zone's own range, and neighbouring zones meet on the boundary position")
    func wholeZonesAndBoundaries() {
        for method in methods {
            let model = model(method)
            for zone in 1...5 {
                let own = model.zoneBPMRange(zone)!
                let positions = model.zoneBPMRange(positions: Double(zone)...Double(zone + 1))!
                #expect(abs(own.lowerBound - positions.lowerBound) < 1e-9 && abs(own.upperBound - positions.upperBound) < 1e-9, "\(method) zone \(zone)")
                // The position of a boundary is the bottom of the upper zone: 4.0 is the top of zone 3 and the bottom of zone 4.
                let boundary = model.zoneRatio(atPosition: Double(zone + 1))!
                let expected = zone < 5 ? model.zoneRatioRange(zone + 1)!.lowerBound : model.zoneRatioRange(5)!.upperBound
                #expect(abs(boundary - expected) < 1e-9, "\(method) boundary \(zone + 1)")
            }
            // The top of zone 5 is the maximum heart rate, except under the threshold method, where it is 120 % of the threshold.
            #expect(model.zoneBPMRange(positions: 5.0...6.0)?.upperBound == (method == .lactateThreshold ? 198 : 190))
        }
    }

    @Test("a position between two boundaries is the interpolation inside its zone")
    func interpolation() {
        let karvonen = model(.karvonen)
        // Zone 3 is 148...162 bpm: 3.4 is 40 % up.
        #expect(abs(karvonen.zoneBPMRange(positions: 3.0...3.4)!.upperBound - 153.6) < 1e-9)
        // Unequal zone widths under the threshold method: the same fraction of a narrower zone is fewer bpm.
        let lactate = model(.lactateThreshold)
        let narrow = lactate.zoneBPMRange(positions: 2.0...2.5)!
        let wide = lactate.zoneBPMRange(positions: 3.0...3.5)!
        #expect(narrow.upperBound - narrow.lowerBound < wide.upperBound - wide.lowerBound)
    }

    @Test("positions outside 1.0 to 6.0, or a method without its reference heart rate, have no range")
    func unavailable() {
        for method in methods {
            let model = model(method)
            #expect(model.zoneRatio(atPosition: 0.99) == nil && model.zoneRatio(atPosition: 6.01) == nil)
            #expect(model.zoneBPMRange(positions: 0.5...2.0) == nil && model.zoneBPMRange(positions: 4.0...6.5) == nil)
        }
        let noThreshold = HeartRateZoneModel(restingHeartRateBPM: 50, maxHeartRateBPM: 190, method: .lactateThreshold)
        #expect(noThreshold.zoneBPMRange(positions: 3.0...3.4) == nil)
        #expect(noThreshold.intensityRatio(for: .heartRateZoneRange(3.0...3.4)) == 0.75)
    }

    @Test("the intensity of positions is the average of their two ends, as the bpm range it becomes")
    func intensityOfPositions() {
        for method in methods {
            let model = model(method)
            for range in [3.0...3.4, 2.5...3.5, 1.2...4.9] {
                let bpm = model.zoneBPMRange(positions: range)!
                let sent = model.intensityRatio(for: .heartRateRange(bpm.lowerBound, bpm.upperBound))
                #expect(abs(model.intensityRatio(for: .heartRateZoneRange(range)) - sent) < 1e-9, "\(method) \(range)")
            }
        }
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
