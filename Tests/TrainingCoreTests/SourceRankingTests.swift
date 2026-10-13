import Foundation
import Testing
@testable import TrainingCore

@Suite("Source reliability ranking")
struct SourceRankingTests {
    private let id = UUID()

    private let day = Date(timeIntervalSince1970: 1_700_000_000)
    private let dayLength: TimeInterval = 86_400

    @Test("max heart rate sources rank formula < manual < workout < field test < a fresh lab test")
    func maxHeartRateOrder() {
        let ordered: [MaxHeartRateSource] = [
            .formula, .manual, .workout(activityID: id), .fieldTest(activityID: id), .labTest(measuredOn: day)
        ]

        #expect(ordered.map { $0.reliabilityRank(asOf: day) } == [0, 1, 2, 3, 4])
    }

    @Test("lactate threshold sources rank manual < field test < a fresh lab test")
    func lactateThresholdOrder() {
        let ordered: [LactateThresholdSource] = [.manual, .fieldTest(activityID: id), .labTest(measuredOn: day)]

        #expect(ordered.map { $0.reliabilityRank(asOf: day) } == [0, 1, 2])
    }

    @Test("a max heart rate lab test keeps its rank for two years, then ranks with a workout, above a formula")
    func maxHeartRateLabTestAges() {
        let lab = MaxHeartRateSource.labTest(measuredOn: day)
        let twoYears = MaxHeartRateSource.labTestFreshness

        #expect(lab.reliabilityRank(asOf: day.addingTimeInterval(twoYears)) == 4)
        #expect(lab.reliabilityRank(asOf: day.addingTimeInterval(twoYears + dayLength)) == 2)
        #expect(MaxHeartRateSource.labTestFreshness == 2 * 365 * dayLength)
        // A lab test dated after "today" isn't aged.
        #expect(lab.reliabilityRank(asOf: day.addingTimeInterval(-dayLength)) == 4)
    }

    @Test("a lactate threshold lab test is worth less than a new field test after about three months")
    func lactateThresholdLabTestAges() {
        let lab = LactateThresholdSource.labTest(measuredOn: day)
        let fieldTest = LactateThresholdSource.fieldTest(activityID: id)
        let fresh = day.addingTimeInterval(60 * dayLength)
        let stale = day.addingTimeInterval(120 * dayLength)

        #expect(!lab.isReplaceable(by: fieldTest, asOf: fresh))
        #expect(lab.isReplaceable(by: fieldTest, asOf: stale))
        // An old lab figure is still no better than a typed-in one, but not worse.
        #expect(lab.isReplaceable(by: .manual, asOf: stale))
        #expect(!lab.isReplaceable(by: .manual, asOf: fresh))
    }

    @Test("an old lab-tested max is replaceable by a field test but never by a formula")
    func oldLabTestVersusFormula() {
        let lab = MaxHeartRateSource.labTest(measuredOn: day)
        let later = day.addingTimeInterval(3 * 365 * dayLength)

        #expect(lab.isReplaceable(by: .fieldTest(activityID: id), asOf: later))
        #expect(!lab.isReplaceable(by: .formula, asOf: later))
        #expect(!lab.isReplaceable(by: .manual, asOf: later))
    }

    @Test("a source may be replaced by one at least as reliable, never by a less reliable one")
    func replaceability() {
        #expect(MaxHeartRateSource.formula.isReplaceable(by: .formula, asOf: day))
        #expect(MaxHeartRateSource.formula.isReplaceable(by: .labTest(measuredOn: day), asOf: day))
        #expect(!MaxHeartRateSource.manual.isReplaceable(by: .formula, asOf: day))
        #expect(!MaxHeartRateSource.workout(activityID: id).isReplaceable(by: .formula, asOf: day))
        #expect(MaxHeartRateSource.fieldTest(activityID: id).isReplaceable(by: .fieldTest(activityID: UUID()), asOf: day))
        #expect(!MaxHeartRateSource.labTest(measuredOn: day).isReplaceable(by: .fieldTest(activityID: id), asOf: day))
        #expect(!MaxHeartRateSource.labTest(measuredOn: day).isReplaceable(by: .manual, asOf: day))
        #expect(!LactateThresholdSource.fieldTest(activityID: id).isReplaceable(by: .manual, asOf: day))
    }

    @Test("the lab-test sources round-trip through the settings' encoding")
    func labTestCodable() throws {
        let settings = HeartRateZoneSettings(
            effectiveDate: Date(timeIntervalSince1970: 1_700_000_000), restingHeartRateBPM: 50, maxHeartRateBPM: 185,
            maxHeartRateSource: .labTest(measuredOn: day), lactateThresholdHeartRateBPM: 168,
            lactateThresholdSource: .labTest(measuredOn: day)
        )

        let decoded = try JSONDecoder().decode(HeartRateZoneSettings.self, from: JSONEncoder().encode(settings))

        #expect(decoded == settings)
        #expect(decoded.maxHeartRateSource == .labTest(measuredOn: day))
        #expect(decoded.lactateThresholdSource == .labTest(measuredOn: day))
    }

    @Test("a field test result flags that it would replace a lab-tested value")
    func resultFlagsLabTest() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let ramp: [Double] = stride(from: 150.0, to: 184, by: 10).dropFirst().map { $0 }
        let bpms: [Double] = Array(repeating: 150.0, count: 48) + ramp + Array(repeating: 184.0, count: 24)
            + ramp.reversed() + Array(repeating: 150.0, count: 48)
        var samples: [HeartRateSample] = []
        for (index, bpm) in bpms.enumerated() {
            samples.append(HeartRateSample(time: start.addingTimeInterval(Double(index) * 5), bpm: bpm))
        }
        let activity = Activity(source: .healthKit(UUID()), sport: .running, start: start, duration: 600, heartRate: samples)
        let workout = try BuiltInWorkoutTemplates.maxHRTest.instantiate()
        func settings(_ source: MaxHeartRateSource) -> HeartRateZoneSettings {
            HeartRateZoneSettings(
                effectiveDate: .distantPast, restingHeartRateBPM: 50, maxHeartRateBPM: 190, maxHeartRateSource: source
            )
        }

        let overLab = try FieldTestMeasurer().measure(
            activity, workout: workout, settings: settings(.labTest(measuredOn: start.addingTimeInterval(-30 * dayLength)))
        )
        let overOldLab = try FieldTestMeasurer().measure(
            activity, workout: workout, settings: settings(.labTest(measuredOn: start.addingTimeInterval(-800 * dayLength)))
        )
        let overFormula = try FieldTestMeasurer().measure(activity, workout: workout, settings: settings(.formula))
        let overWorkout = try FieldTestMeasurer().measure(activity, workout: workout, settings: settings(.workout(activityID: UUID())))

        #expect(overLab?.replacesMoreReliableSource == true)
        #expect(overOldLab?.replacesMoreReliableSource == false)
        #expect(overFormula?.replacesMoreReliableSource == false)
        #expect(overWorkout?.replacesMoreReliableSource == false)
    }
}
