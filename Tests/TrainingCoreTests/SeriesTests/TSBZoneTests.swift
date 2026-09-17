import Testing
@testable import TrainingCore

@Suite("TSBZone")
struct TSBZoneTests {
    @Test(
        "init(tsb:) classifies a value into the correct zone, using PlanGuardrails' defaults",
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

    @Test("race/detraining boundaries track a custom PlanGuardrails, not fixed literals")
    func racBoundariesTrackGuardrails() {
        let guardrails = PlanGuardrails(minTSBOnRaceDay: 8, maxTSBOnRaceDay: 20)

        #expect(TSBZone(tsb: 7.9, guardrails: guardrails) == .recovery)
        #expect(TSBZone(tsb: 8.0, guardrails: guardrails) == .race)
        #expect(TSBZone(tsb: 19.9, guardrails: guardrails) == .race)
        #expect(TSBZone(tsb: 20.0, guardrails: guardrails) == .detraining)
    }

    @Test("a NaN tsb falls back to injuryRisk rather than crashing or matching every zone")
    func nanFallsBackToInjuryRisk() {
        #expect(TSBZone(tsb: .nan) == .injuryRisk)
    }

    @Test("FitnessMetrics.tsbZone(guardrails:) classifies its own tsb, defaulting to PlanGuardrails()")
    func fitnessMetricsExposesTSBZone() {
        let metrics = FitnessMetrics(
            day: .now, load: 0, ctl: 0, atl: 0, tsb: -40, monotony: .nan, strain: .nan,
            isProjected: false, isWarmingUp: false
        )

        #expect(metrics.tsbZone() == .injuryRisk)
    }
}
