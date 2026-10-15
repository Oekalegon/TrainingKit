import Foundation
import Testing
@testable import TrainingCore

@Suite("PlanEvaluator cycle-aware rules")
struct PlanEvaluatorCycleAwareRulesTests {
    let evaluator = PlanEvaluator()

    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    private func week(_ weekIndex: Int) -> ClosedRange<Date> {
        day(weekIndex * 7)...day(weekIndex * 7 + 6)
    }

    /// One `FitnessMetrics` entry per day of `week`, each contributing `dailyLoad` (so the week's
    /// total load is `dailyLoad * 7`), with `ctl`/`tsb` only meaningful on the week's boundary days.
    private func metricsForWeek(_ weekIndex: Int, dailyLoad: Double, ctl: Double = 50, tsb: Double = 0, isWarmingUp: Bool = false) -> [FitnessMetrics] {
        (0..<7).map {
            FitnessMetrics(day: day(weekIndex * 7 + $0), load: dailyLoad, ctl: ctl, atl: ctl, tsb: tsb, monotony: 1, strain: dailyLoad, isProjected: false, isWarmingUp: isWarmingUp)
        }
    }

    private func micro(week weekIndex: Int, phase: CyclePhase, parentID: UUID) -> TrainingCycle {
        TrainingCycle(level: .micro, phase: phase, name: "Week \(weekIndex)", dateRange: week(weekIndex), parentID: parentID)
    }

    // MARK: - Cycles empty

    @Test("cycle-aware rules don't run when cycles is empty")
    func cycleAwareRulesSkippedWithoutCycles() {
        let metrics = metricsForWeek(0, dailyLoad: 100) + metricsForWeek(1, dailyLoad: 200) // would trip buildProgression if cycles were supplied

        let evaluation = evaluator.evaluate(metrics, races: [], cycles: [])

        #expect(evaluation.findings.allSatisfy { $0.rule != .buildProgression })
    }

    // MARK: - Build progression

    @Test("build progression too aggressive fires risk; negative progression fires info; skips recovery micros in between")
    func buildProgressionBounds() {
        let mesoID = UUID()
        let cycles = [
            micro(week: 0, phase: .build, parentID: mesoID), // baseline: 100
            micro(week: 1, phase: .recovery, parentID: mesoID), // skipped when comparing builds
            micro(week: 2, phase: .build, parentID: mesoID), // +50% vs week 0 -> risk
            micro(week: 3, phase: .build, parentID: mesoID), // -20% vs week 2 -> info
        ]
        let metrics = metricsForWeek(0, dailyLoad: 100)
            + metricsForWeek(1, dailyLoad: 20)
            + metricsForWeek(2, dailyLoad: 150)
            + metricsForWeek(3, dailyLoad: 120)

        let evaluation = evaluator.evaluate(metrics, races: [], cycles: cycles)

        let findings = evaluation.findings.filter { $0.rule == .buildProgression }
        #expect(findings.count == 2)
        #expect(findings.first { $0.day == week(2).lowerBound }?.severity == .risk)
        #expect(findings.first { $0.day == week(3).lowerBound }?.severity == .info)
    }

    // MARK: - Micro lengths other than 7 days

    /// Micros of `length` days back to back from day 0, one per phase, and a metrics series with
    /// each micro's days at its `dailyLoad`.
    private func layout(length: Int, _ micros: [(phase: CyclePhase, dailyLoad: Double)]) -> (cycles: [TrainingCycle], metrics: [FitnessMetrics]) {
        let mesoID = UUID()
        var cycles: [TrainingCycle] = []
        var metrics: [FitnessMetrics] = []
        for (index, entry) in micros.enumerated() {
            let start = index * length
            cycles.append(TrainingCycle(level: .micro, phase: entry.phase, name: "Micro \(index)", dateRange: day(start)...day(start + length - 1), parentID: mesoID))
            metrics += (0..<length).map {
                FitnessMetrics(day: day(start + $0), load: entry.dailyLoad, ctl: 50, atl: 50, tsb: 0, monotony: 1, strain: entry.dailyLoad, isProjected: false, isWarmingUp: false)
            }
        }
        return (cycles, metrics)
    }

    @Test("build progression compares mean daily load, so 10- and 14-day micros read like 7-day ones")
    func buildProgressionPerDayForLongMicros() {
        for length in [10, 14] {
            let (good, goodMetrics) = layout(length: length, [(.build, 100), (.build, 105)])
            #expect(!evaluator.evaluate(goodMetrics, races: [], cycles: good).findings.contains { $0.rule == .buildProgression }, "micro length \(length)")

            let (bad, badMetrics) = layout(length: length, [(.build, 100), (.build, 130)])
            let findings = evaluator.evaluate(badMetrics, races: [], cycles: bad).findings.filter { $0.rule == .buildProgression }
            #expect(findings.count == 1 && findings[0].severity == .risk && findings[0].day == day(length), "micro length \(length)")
        }
    }

    @Test("a shorter first micro isn't mistaken for a lighter build by total load")
    func unequalMicroLengthsCompareByDay() {
        let mesoID = UUID()
        let cycles = [
            TrainingCycle(level: .micro, phase: .build, name: "Trimmed", dateRange: day(0)...day(3), parentID: mesoID),
            TrainingCycle(level: .micro, phase: .build, name: "Full", dateRange: day(4)...day(13), parentID: mesoID),
        ]
        // 4 days at 100 = 400 total; 10 days at 105 = 1050 total, but only +5% per day.
        let metrics = (0...3).map { FitnessMetrics(day: day($0), load: 100, ctl: 50, atl: 50, tsb: 0, monotony: 1, strain: 100, isProjected: false, isWarmingUp: false) }
            + (4...13).map { FitnessMetrics(day: day($0), load: 105, ctl: 50, atl: 50, tsb: 0, monotony: 1, strain: 105, isProjected: false, isWarmingUp: false) }
        #expect(!evaluator.evaluate(metrics, races: [], cycles: cycles).findings.contains { $0.rule == .buildProgression })
    }
}
