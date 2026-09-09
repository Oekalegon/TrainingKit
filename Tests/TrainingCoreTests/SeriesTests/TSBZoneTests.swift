import Testing
@testable import TrainingCore

@Suite("TSBZone")
struct TSBZoneTests {
    @Test(
        "init(tsb:) classifies a value into the correct zone",
        arguments: [
            (-100.0, TSBZone.injuryRisk),
            (-30.1, .injuryRisk),
            (-30.0, .training),
            (-20.0, .training),
            (-10.1, .training),
            (-10.0, .recovery),
            (0.0, .recovery),
            (4.9, .recovery),
            (5.0, .race),
            (15.0, .race),
            (24.9, .race),
            (25.0, .detraining),
            (100.0, .detraining),
        ]
    )
    func classifiesValue(tsb: Double, expectedZone: TSBZone) {
        #expect(TSBZone(tsb: tsb) == expectedZone)
    }

    @Test("FitnessMetrics.tsbZone classifies its own tsb")
    func fitnessMetricsExposesTSBZone() {
        let metrics = FitnessMetrics(
            day: .now, load: 0, ctl: 0, atl: 0, tsb: -40, monotony: .nan, strain: .nan,
            isProjected: false, isWarmingUp: false
        )

        #expect(metrics.tsbZone == .injuryRisk)
    }
}
