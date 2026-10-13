import Foundation
import Testing
@testable import TrainingCore

@Suite("Source reliability ranking")
struct SourceRankingTests {
    private let id = UUID()

    @Test("max heart rate sources rank formula < manual < workout < field test < lab test")
    func maxHeartRateOrder() {
        let ordered: [MaxHeartRateSource] = [.formula, .manual, .workout(activityID: id), .fieldTest(activityID: id), .labTest]

        #expect(ordered.map(\.reliabilityRank) == [0, 1, 2, 3, 4])
    }

    @Test("lactate threshold sources rank manual < field test < lab test")
    func lactateThresholdOrder() {
        let ordered: [LactateThresholdSource] = [.manual, .fieldTest(activityID: id), .labTest]

        #expect(ordered.map(\.reliabilityRank) == [0, 1, 2])
    }

    @Test("a source may be replaced by one at least as reliable, never by a less reliable one")
    func replaceability() {
        #expect(MaxHeartRateSource.formula.isReplaceable(by: .formula))
        #expect(MaxHeartRateSource.formula.isReplaceable(by: .labTest))
        #expect(!MaxHeartRateSource.manual.isReplaceable(by: .formula))
        #expect(!MaxHeartRateSource.workout(activityID: id).isReplaceable(by: .formula))
        #expect(MaxHeartRateSource.fieldTest(activityID: id).isReplaceable(by: .fieldTest(activityID: UUID())))
        #expect(!MaxHeartRateSource.labTest.isReplaceable(by: .fieldTest(activityID: id)))
        #expect(!MaxHeartRateSource.labTest.isReplaceable(by: .manual))

        #expect(LactateThresholdSource.manual.isReplaceable(by: .fieldTest(activityID: id)))
        #expect(!LactateThresholdSource.labTest.isReplaceable(by: .fieldTest(activityID: id)))
        #expect(!LactateThresholdSource.fieldTest(activityID: id).isReplaceable(by: .manual))
    }

    @Test("the lab-test sources round-trip through the settings' encoding")
    func labTestCodable() throws {
        let settings = HeartRateZoneSettings(
            effectiveDate: Date(timeIntervalSince1970: 1_700_000_000), restingHeartRateBPM: 50, maxHeartRateBPM: 185,
            maxHeartRateSource: .labTest, lactateThresholdHeartRateBPM: 168, lactateThresholdSource: .labTest
        )

        let decoded = try JSONDecoder().decode(HeartRateZoneSettings.self, from: JSONEncoder().encode(settings))

        #expect(decoded == settings)
        #expect(decoded.maxHeartRateSource == .labTest)
        #expect(decoded.lactateThresholdSource == .labTest)
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

        let overLab = try FieldTestMeasurer().measure(activity, workout: workout, settings: settings(.labTest))
        let overFormula = try FieldTestMeasurer().measure(activity, workout: workout, settings: settings(.formula))
        let overWorkout = try FieldTestMeasurer().measure(activity, workout: workout, settings: settings(.workout(activityID: UUID())))

        #expect(overLab?.replacesMoreReliableSource == true)
        #expect(overFormula?.replacesMoreReliableSource == false)
        #expect(overWorkout?.replacesMoreReliableSource == false)
    }
}
