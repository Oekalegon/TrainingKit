import Foundation
import Testing
@testable import TrainingCore

@Suite("PlanEvaluator integration with CycleLayoutBuilder")
struct PlanEvaluatorIntegrationTests {
    @Test("meso-progress lookups match CycleLayoutBuilder's actual day boundaries, not just hand-picked test dates")
    func mesoProgressMatchesRealLayoutBoundaries() {
        let athlete = AthleteProfile.fixture()
        let raceDate = Date(timeIntervalSince1970: 1_700_000_000)
        let race = Race(name: "Goal Race", date: raceDate, priority: .a)
        let macro = MacroTemplate(name: "Block", mesoBlocks: [MacroTemplate.MesoBlock(phase: .build, microCount: 5)])
        let meso = MesocycleTemplate.threeToOne

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = athlete.timeZone
        let raceDay = calendar.startOfDay(for: raceDate)
        let start = calendar.date(byAdding: .day, value: -(5 * 7 - 1), to: raceDay)!

        let cycles = CycleLayoutBuilder().layout(from: start, to: race, macro: macro, meso: meso, athlete: athlete)
        #expect(cycles.contains { $0.level == .meso }) // sanity: the layout actually produced a meso

        // A metrics series spanning exactly the layout's range, using the same day boundaries a
        // real DailyLoadSeries/FitnessMetricsCalculator pipeline would produce. CTL rises only
        // 0.05/day for 35 days (1.75 total), under the 2-point minimum, so meso-progress should fire
        // — it only can if its lookup into this series by the meso's own dateRange bounds succeeds.
        var metrics: [FitnessMetrics] = []
        var day = start
        var ctl = 40.0
        while day <= raceDay {
            metrics.append(FitnessMetrics(day: day, load: 50, ctl: ctl, atl: ctl, tsb: 0, monotony: 1.2, strain: 60, isProjected: false, isWarmingUp: false))
            ctl += 0.05
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }

        let evaluation = PlanEvaluator().evaluate(metrics, races: [race], cycles: cycles)

        #expect(evaluation.findings.contains { $0.rule == .mesoProgress && $0.severity == .risk })
    }
}
