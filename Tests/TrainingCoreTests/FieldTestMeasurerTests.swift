import Foundation
import Testing
@testable import TrainingCore

@Suite("FieldTestMeasurer")
struct FieldTestMeasurerTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private let measurer = FieldTestMeasurer()

    private var settings: HeartRateZoneSettings {
        HeartRateZoneSettings(
            effectiveDate: .distantPast, restingHeartRateBPM: 50, maxHeartRateBPM: 178, lactateThresholdHeartRateBPM: 160
        )
    }

    private func lthrWorkout() throws -> StructuredWorkout {
        try BuiltInWorkoutTemplates.lthrTest.instantiate()
    }

    /// Where each of the LTHR test's four blocks runs, in seconds after the start.
    private let lthrBlocks: [ClosedRange<Double>] = [0...600, 600...900, 900...2700, 2700...3000]

    /// A heart rate every `interval` seconds: 140 during the warmup, 150 on the ramp-in, `first` for the
    /// first 10 minutes of the effort, `last` for the last 20, then 130.
    private func lthrSamples(
        first: Double = 160, last: Double = 170, interval: Double = 5, noise: (Int) -> Double = { _ in 0 }
    ) -> [HeartRateSample] {
        var samples: [HeartRateSample] = []
        var index = 0
        var second = 0.0
        while second <= 3000 {
            let base: Double
            switch second {
            case ..<600: base = 140
            case ..<900: base = 150
            case ..<1500: base = first
            case ..<2700: base = last
            default: base = 130
            }
            samples.append(HeartRateSample(time: start.addingTimeInterval(second), bpm: base + noise(index)))
            index += 1
            second += interval
        }
        return samples
    }

    private func recordedSteps(effortSeconds: Double = 1800) -> [ActivityStep] {
        var steps: [ActivityStep] = []
        for (block, range) in lthrBlocks.enumerated() {
            let end = block == 2 ? range.lowerBound + effortSeconds : range.upperBound
            steps.append(ActivityStep(
                block: block, repetition: 0, step: 0,
                start: start.addingTimeInterval(range.lowerBound), end: start.addingTimeInterval(end)
            ))
        }
        return steps
    }

    private func lthrActivity(
        samples: [HeartRateSample], steps: [ActivityStep] = [], duration: Double = 3000
    ) -> Activity {
        Activity(
            source: .healthKit(UUID()), sport: .running, start: start, duration: duration, heartRate: samples, steps: steps
        )
    }

    // MARK: Lactate threshold

    @Test("the LTHR is the average over the last 20 minutes of the recorded effort, not the first 10")
    func lthrFromRecordedSteps() throws {
        let activity = lthrActivity(samples: lthrSamples(), steps: recordedSteps())

        let result = try #require(try measurer.measure(activity, workout: lthrWorkout(), settings: settings))

        #expect(result.measurement == .lactateThresholdHeartRate)
        #expect(result.valueBPM == 170)
        #expect(result.currentBPM == 160)
        #expect(!result.isEstimatedFromPlan)
        #expect(result.changesValue)
    }

    @Test("without recorded steps the effort is located from the plan's timing and flagged as estimated")
    func lthrFromPlanTiming() throws {
        let activity = lthrActivity(samples: lthrSamples())

        let result = try #require(try measurer.measure(activity, workout: lthrWorkout(), settings: settings))

        #expect(result.valueBPM == 170)
        #expect(result.isEstimatedFromPlan)
    }

    @Test("an activity much shorter or longer than the plan can't have its effort located by time")
    func lthrNotLocated() throws {
        let workout = try lthrWorkout()
        for duration in [2000.0, 4000.0] {
            let activity = lthrActivity(samples: lthrSamples(), duration: duration)
            #expect(throws: FieldTestError.effortNotLocated) {
                try measurer.measure(activity, workout: workout, settings: settings)
            }
        }
    }

    @Test("recorded steps that fit the plan but lack the effort don't fall back to the plan's timing")
    func lthrSkippedEffortNotInvented() throws {
        let withoutEffort = recordedSteps().filter { $0.block != 2 }
        let activity = lthrActivity(samples: lthrSamples(), steps: withoutEffort)

        #expect(throws: FieldTestError.effortNotLocated) {
            try measurer.measure(activity, workout: lthrWorkout(), settings: settings)
        }
    }

    @Test("a recording that started two minutes into the warmup puts a cooldown at the plan-timed window's end and is refused")
    func lthrShiftedRecordingRefused() throws {
        // Same total length, but everything happens two minutes earlier in the recording.
        var samples: [HeartRateSample] = []
        for sample in lthrSamples() where sample.time >= start.addingTimeInterval(120) {
            samples.append(HeartRateSample(time: sample.time.addingTimeInterval(-120), bpm: sample.bpm))
        }
        var second = 2880.0
        while second <= 3000 {
            samples.append(HeartRateSample(time: start.addingTimeInterval(second), bpm: 130))
            second += 5
        }
        let activity = lthrActivity(samples: samples)

        #expect(throws: FieldTestError.effortNotLocated) {
            try measurer.measure(activity, workout: lthrWorkout(), settings: settings)
        }
    }

    @Test("a recorded effort under 90% of the planned 30 minutes is refused")
    func lthrEffortTooShort() throws {
        let activity = lthrActivity(samples: lthrSamples(), steps: recordedSteps(effortSeconds: 1500))

        #expect(throws: FieldTestError.effortTooShort(recordedSeconds: 1500)) {
            try measurer.measure(activity, workout: lthrWorkout(), settings: settings)
        }
    }

    @Test("an effort with heart rate for less than 80% of the 20 minutes is refused")
    func lthrInsufficientCoverage() throws {
        let sparse = lthrSamples().filter { $0.time < start.addingTimeInterval(1500) || $0.time > start.addingTimeInterval(1900) }
        let activity = lthrActivity(samples: sparse, steps: recordedSteps())

        #expect(throws: FieldTestError.insufficientHeartRate) {
            try measurer.measure(activity, workout: lthrWorkout(), settings: settings)
        }
    }

    @Test("no heart rate at all is reported as such")
    func lthrNoHeartRate() throws {
        let activity = lthrActivity(samples: [], steps: recordedSteps())

        #expect(throws: FieldTestError.noHeartRate) {
            try measurer.measure(activity, workout: lthrWorkout(), settings: settings)
        }
    }

    @Test("a stuck reading above the plausible maximum is left out, not averaged in")
    func lthrIgnoresImplausibleSamples() throws {
        var samples = lthrSamples()
        for index in samples.indices where abs(samples[index].time.timeIntervalSince(start) - 2000) < 1 {
            samples[index] = HeartRateSample(time: samples[index].time, bpm: 250)
        }
        let activity = lthrActivity(samples: samples, steps: recordedSteps())

        let result = try #require(try measurer.measure(activity, workout: lthrWorkout(), settings: settings))

        #expect(result.valueBPM == 170)
    }

    @Test("seeded sensor noise averages out to within a beat of the true value")
    func lthrNoiseRobust() throws {
        var generator = SeededGenerator(seed: 154)
        let noise: [Double] = (0..<700).map { _ in Double.random(in: -4...4, using: &generator) }
        let activity = lthrActivity(samples: lthrSamples(noise: { noise[$0] }), steps: recordedSteps())

        let result = try #require(try measurer.measure(activity, workout: lthrWorkout(), settings: settings))

        #expect(abs(result.valueBPM - 170) <= 1)
    }

    @Test("the average is weighted by time, so a burst of dense samples doesn't dominate")
    func lthrTimeWeighted() throws {
        // Every 5 s at 170 except the last two minutes of the effort, sampled every second at 180.
        var samples = lthrSamples().filter { $0.time < start.addingTimeInterval(2580) || $0.time > start.addingTimeInterval(2700) }
        var second = 2580.0
        while second <= 2700 {
            samples.append(HeartRateSample(time: start.addingTimeInterval(second), bpm: 180))
            second += 1
        }
        let activity = lthrActivity(samples: samples, steps: recordedSteps())

        let result = try #require(try measurer.measure(activity, workout: lthrWorkout(), settings: settings))

        // 18 minutes at 170 and 2 at 180 is 171, however many samples each has.
        #expect(result.valueBPM == 171)
    }

    // MARK: Max heart rate

    /// 150 bpm that ramps up 10 bpm per 5 s sample (a real heart's pace, below the detector's
    /// cadence-lock threshold) to hold `peak` for two minutes, then ramps back down. A `peak` of 150
    /// or less is held throughout.
    private func maxHRActivity(peak: Double) -> Activity {
        let base = min(150.0, peak)
        let ramp: [Double] = stride(from: base, to: peak, by: 10).dropFirst().map { $0 }
        let bpms: [Double] = Array(repeating: base, count: 48) + ramp + Array(repeating: peak, count: 24)
            + ramp.reversed() + Array(repeating: base, count: 48)
        var samples: [HeartRateSample] = []
        for (index, bpm) in bpms.enumerated() {
            samples.append(HeartRateSample(time: start.addingTimeInterval(Double(index) * 5), bpm: bpm))
        }
        return Activity(source: .healthKit(UUID()), sport: .running, start: start, duration: 600, heartRate: samples)
    }

    @Test("the max HR is the highest heart rate held, and may be above the value on record")
    func maxHRRaises() throws {
        let workout = try BuiltInWorkoutTemplates.maxHRTest.instantiate()

        let result = try #require(try measurer.measure(maxHRActivity(peak: 184), workout: workout, settings: settings))

        #expect(result.measurement == .maxHeartRate)
        #expect(result.valueBPM == 184)
        #expect(result.currentBPM == 178)
        #expect(!result.isEstimatedFromPlan)
    }

    @Test("a test that falls short of the value on record still gives a (lower) result")
    func maxHRLowers() throws {
        let workout = try BuiltInWorkoutTemplates.maxHRTest.instantiate()

        let result = try #require(try measurer.measure(maxHRActivity(peak: 170), workout: workout, settings: settings))

        #expect(result.valueBPM == 170)
        #expect(result.changesValue)
    }

    @Test("a result equal to the value on record changes nothing")
    func maxHREqual() throws {
        let workout = try BuiltInWorkoutTemplates.maxHRTest.instantiate()

        let result = try #require(try measurer.measure(maxHRActivity(peak: 178), workout: workout, settings: settings))

        #expect(!result.changesValue)
    }

    @Test("a short spike isn't taken for the maximum")
    func maxHRIgnoresSpike() throws {
        let workout = try BuiltInWorkoutTemplates.maxHRTest.instantiate()
        var activity = maxHRActivity(peak: 175)
        activity.heartRate[75] = HeartRateSample(time: activity.heartRate[75].time, bpm: 205)

        let result = try #require(try measurer.measure(activity, workout: workout, settings: settings))

        #expect(result.valueBPM == 175)
    }

    @Test("a max HR test with no heart rate, or a value at or below resting, is refused")
    func maxHRRefusals() throws {
        let workout = try BuiltInWorkoutTemplates.maxHRTest.instantiate()
        let empty = Activity(source: .healthKit(UUID()), sport: .running, start: start, duration: 600)

        #expect(throws: FieldTestError.noHeartRate) { try measurer.measure(empty, workout: workout, settings: settings) }
        #expect(throws: FieldTestError.implausibleValue(bpm: 50)) {
            try measurer.measure(maxHRActivity(peak: 50), workout: workout, settings: settings)
        }
    }

    @Test("an ordinary workout isn't a test")
    func generalIsNil() throws {
        let workout = try BuiltInWorkoutTemplates.easyRun.instantiate()

        #expect(try measurer.measure(maxHRActivity(peak: 184), workout: workout, settings: settings) == nil)
    }
}

/// A deterministic generator, so a noise test fails the same way every run.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}
