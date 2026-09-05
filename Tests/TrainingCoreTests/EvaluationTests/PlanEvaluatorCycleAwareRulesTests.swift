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
        let metrics = metricsForWeek(0, dailyLoad: 1000) // would trip consecutiveLoad/recovery if cycles were supplied

        let evaluation = evaluator.evaluate(metrics, races: [], cycles: [])

        #expect(evaluation.findings.allSatisfy { $0.rule != .recoveryMicro && $0.rule != .buildProgression && $0.rule != .mesoProgress && $0.rule != .taperShape && $0.rule != .consecutiveLoad })
    }

    // MARK: - Recovery micro

    @Test("a recovery micro that doesn't drop load enough fires risk")
    func recoveryMicroDoesntRecover() {
        let mesoID = UUID()
        let cycles = [micro(week: 0, phase: .build, parentID: mesoID), micro(week: 1, phase: .recovery, parentID: mesoID)]
        let metrics = metricsForWeek(0, dailyLoad: 100) + metricsForWeek(1, dailyLoad: 90) // 0.9 > 0.65 default

        let evaluation = evaluator.evaluate(metrics, races: [], cycles: cycles)

        let finding = evaluation.findings.first { $0.rule == .recoveryMicro }
        #expect(finding != nil)
        #expect(finding?.severity == .risk)
        #expect(finding?.day == week(1).lowerBound)
    }

    @Test("a recovery micro that drops load enough doesn't fire")
    func recoveryMicroRecoversProperly() {
        let mesoID = UUID()
        let cycles = [micro(week: 0, phase: .build, parentID: mesoID), micro(week: 1, phase: .recovery, parentID: mesoID)]
        let metrics = metricsForWeek(0, dailyLoad: 100) + metricsForWeek(1, dailyLoad: 50) // 0.5 <= 0.65

        let evaluation = evaluator.evaluate(metrics, races: [], cycles: cycles)

        #expect(!evaluation.findings.contains { $0.rule == .recoveryMicro })
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

    // MARK: - Meso progress

    @Test("insufficient CTL gain across a build/base meso fires risk")
    func mesoProgressInsufficientGain() {
        let macroID = UUID()
        let meso = TrainingCycle(level: .meso, phase: .build, name: "Meso 1", dateRange: week(0), parentID: macroID)
        let cycles = [meso]
        // CTL at the meso's start day and end day gain only 1, below the default minimum of 2.
        var metrics = metricsForWeek(0, dailyLoad: 50, ctl: 50)
        metrics[metrics.count - 1] = FitnessMetrics(day: metrics.last!.day, load: 50, ctl: 51, atl: 50, tsb: 0, monotony: 1, strain: 50, isProjected: false, isWarmingUp: false)

        let evaluation = evaluator.evaluate(metrics, races: [], cycles: cycles)

        let finding = evaluation.findings.first { $0.rule == .mesoProgress }
        #expect(finding != nil)
        #expect(finding?.severity == .risk)
        #expect(finding?.day == meso.dateRange.lowerBound)
    }

    @Test("sufficient CTL gain across a build meso doesn't fire, and a taper meso is never checked by this rule")
    func mesoProgressSufficientGainAndTaperExcluded() {
        let macroID = UUID()
        let buildMeso = TrainingCycle(level: .meso, phase: .build, name: "Meso 1", dateRange: week(0), parentID: macroID)
        let taperMeso = TrainingCycle(level: .meso, phase: .taper, name: "Meso 2", dateRange: week(1), parentID: macroID)
        var metrics = metricsForWeek(0, dailyLoad: 50, ctl: 50) + metricsForWeek(1, dailyLoad: 20, ctl: 50)
        metrics[6] = FitnessMetrics(day: day(6), load: 50, ctl: 55, atl: 50, tsb: 0, monotony: 1, strain: 50, isProjected: false, isWarmingUp: false) // +5 gain

        let evaluation = evaluator.evaluate(metrics, races: [], cycles: [buildMeso, taperMeso])

        #expect(!evaluation.findings.contains { $0.rule == .mesoProgress })
    }

    @Test("meso progress is skipped when either boundary day is still warming up")
    func mesoProgressSkipsWarmingUpBoundary() {
        let macroID = UUID()
        let meso = TrainingCycle(level: .meso, phase: .build, name: "Meso 1", dateRange: week(0), parentID: macroID)
        // Same insufficient-gain shape as mesoProgressInsufficientGain, but the end boundary is
        // still warming up — should not fire even though the raw gain is below the minimum.
        var metrics = metricsForWeek(0, dailyLoad: 50, ctl: 50, isWarmingUp: true)
        metrics[metrics.count - 1] = FitnessMetrics(day: metrics.last!.day, load: 50, ctl: 51, atl: 50, tsb: 0, monotony: 1, strain: 50, isProjected: false, isWarmingUp: true)

        let evaluation = evaluator.evaluate(metrics, races: [], cycles: [meso])

        #expect(!evaluation.findings.contains { $0.rule == .mesoProgress })
    }

    // MARK: - Taper shape

    @Test("too much CTL dropped across a taper meso fires risk, and TSB not rising fires warning")
    func taperShapeBadTaper() {
        let macroID = UUID()
        let taper = TrainingCycle(level: .meso, phase: .taper, name: "Taper", dateRange: week(0), parentID: macroID)
        var metrics = metricsForWeek(0, dailyLoad: 20, ctl: 50, tsb: 0)
        // End of taper: CTL dropped 20% (over the 10% default) and TSB didn't rise.
        metrics[6] = FitnessMetrics(day: day(6), load: 20, ctl: 40, atl: 30, tsb: -2, monotony: 1, strain: 20, isProjected: false, isWarmingUp: false)

        let evaluation = evaluator.evaluate(metrics, races: [], cycles: [taper])

        let findings = evaluation.findings.filter { $0.rule == .taperShape }
        #expect(findings.contains { $0.severity == .risk }) // CTL dropped too much
        #expect(findings.contains { $0.severity == .warning }) // TSB didn't rise
    }

    @Test("a well-shaped taper doesn't fire")
    func taperShapeGoodTaper() {
        let macroID = UUID()
        let taper = TrainingCycle(level: .meso, phase: .taper, name: "Taper", dateRange: week(0), parentID: macroID)
        var metrics = metricsForWeek(0, dailyLoad: 20, ctl: 50, tsb: 0)
        // CTL drops only 4% and TSB rises.
        metrics[6] = FitnessMetrics(day: day(6), load: 20, ctl: 48, atl: 30, tsb: 18, monotony: 1, strain: 20, isProjected: false, isWarmingUp: false)

        let evaluation = evaluator.evaluate(metrics, races: [], cycles: [taper])

        #expect(!evaluation.findings.contains { $0.rule == .taperShape })
    }

    @Test("TSB-not-rising still fires even when the CTL-drop check can't run (start CTL is zero)")
    func taperShapeTSBCheckIsIndependentOfCTLCheck() {
        let macroID = UUID()
        let taper = TrainingCycle(level: .meso, phase: .taper, name: "Taper", dateRange: week(0), parentID: macroID)
        var metrics = metricsForWeek(0, dailyLoad: 20, ctl: 0, tsb: 0)
        // Start CTL is 0 (the drop-fraction check can't divide by it), but TSB still doesn't rise.
        metrics[6] = FitnessMetrics(day: day(6), load: 20, ctl: 0, atl: 0, tsb: -2, monotony: 1, strain: 20, isProjected: false, isWarmingUp: false)

        let evaluation = evaluator.evaluate(metrics, races: [], cycles: [taper])

        let findings = evaluation.findings.filter { $0.rule == .taperShape }
        #expect(findings.count == 1)
        #expect(findings.first?.severity == .warning)
    }

    @Test("taper shape is skipped when either boundary day is still warming up")
    func taperShapeSkipsWarmingUpBoundary() {
        let macroID = UUID()
        let taper = TrainingCycle(level: .meso, phase: .taper, name: "Taper", dateRange: week(0), parentID: macroID)
        var metrics = metricsForWeek(0, dailyLoad: 20, ctl: 50, tsb: 0, isWarmingUp: true)
        metrics[6] = FitnessMetrics(day: day(6), load: 20, ctl: 40, atl: 30, tsb: -2, monotony: 1, strain: 20, isProjected: false, isWarmingUp: true)

        let evaluation = evaluator.evaluate(metrics, races: [], cycles: [taper])

        #expect(!evaluation.findings.contains { $0.rule == .taperShape })
    }

    // MARK: - Consecutive load

    @Test("more consecutive non-recovery micros than allowed fires risk; a recovery micro resets the count")
    func consecutiveLoadRule() {
        let mesoID = UUID()
        let cycles = [
            micro(week: 0, phase: .build, parentID: mesoID),
            micro(week: 1, phase: .build, parentID: mesoID),
            micro(week: 2, phase: .build, parentID: mesoID),
            micro(week: 3, phase: .build, parentID: mesoID), // 4th consecutive, over the default max of 3
            micro(week: 4, phase: .recovery, parentID: mesoID), // resets
            micro(week: 5, phase: .build, parentID: mesoID),
        ]
        let metrics = (0...5).flatMap { metricsForWeek($0, dailyLoad: 50) }

        let evaluation = evaluator.evaluate(metrics, races: [], cycles: cycles)

        let findings = evaluation.findings.filter { $0.rule == .consecutiveLoad }
        #expect(findings.count == 1)
        #expect(findings.first?.day == week(3).lowerBound)
        #expect(findings.first?.value == 4)
        #expect(findings.first?.threshold == 3)
    }
}
