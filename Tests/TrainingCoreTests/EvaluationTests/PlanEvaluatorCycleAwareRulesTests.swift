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
        #expect(findings.first?.value == 21)
        #expect(findings.first?.threshold == 21)
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

    @Test("consecutive load counts days, so the same default flags the 4th 10-day micro but already the 3rd 14-day one")
    func consecutiveLoadInDaysForLongMicros() {
        for length in [10, 14] {
            let (cycles, metrics) = layout(length: length, Array(repeating: (CyclePhase.build, 50.0), count: 4))
            let findings = evaluator.evaluate(metrics, races: [], cycles: cycles).findings.filter { $0.rule == .consecutiveLoad }
            // 10-day micros start at day 0, 10, 20, 30: the 4th starts after 30 >= 21 days.
            // 14-day micros start at 0, 14, 28, 42: the 3rd starts after 28 >= 21 days.
            let expectedDays = length == 10 ? [30] : [28, 42]
            #expect(findings.map { Int($0.value) } == expectedDays, "micro length \(length)")
        }
    }

    @Test("consecutive load honours a threshold raised for long micros, and a recovery micro resets it")
    func consecutiveLoadThresholdAndReset() {
        let (cycles, metrics) = layout(length: 14, [(.build, 50), (.build, 50), (.recovery, 20), (.build, 50), (.build, 50)])
        var guardrails = PlanGuardrails()
        guardrails.maxDaysWithoutRecovery = 28
        #expect(!evaluator.evaluate(metrics, races: [], cycles: cycles, guardrails: guardrails).findings.contains { $0.rule == .consecutiveLoad })

        guardrails.maxDaysWithoutRecovery = 14
        let findings = evaluator.evaluate(metrics, races: [], cycles: cycles, guardrails: guardrails).findings.filter { $0.rule == .consecutiveLoad }
        #expect(findings.map(\.day) == [day(14), day(56)])
    }

    @Test("recovery and build progression compare mean daily load, so 10- and 14-day micros read like 7-day ones")
    func perDayLoadComparison() {
        for length in [10, 14] {
            let (good, goodMetrics) = layout(length: length, [(.build, 100), (.recovery, 50), (.build, 105)])
            let goodFindings = evaluator.evaluate(goodMetrics, races: [], cycles: good).findings
            #expect(!goodFindings.contains { $0.rule == .recoveryMicro || $0.rule == .buildProgression }, "micro length \(length)")

            let (bad, badMetrics) = layout(length: length, [(.build, 100), (.recovery, 90), (.build, 130)])
            let badFindings = evaluator.evaluate(badMetrics, races: [], cycles: bad).findings
            #expect(badFindings.contains { $0.rule == .recoveryMicro && $0.day == day(length) }, "micro length \(length)")
            #expect(badFindings.contains { $0.rule == .buildProgression && $0.severity == .risk && $0.day == day(2 * length) }, "micro length \(length)")
        }
    }

    @Test("a shorter first micro isn't mistaken for a recovery by total load")
    func unequalMicroLengthsCompareByDay() {
        let mesoID = UUID()
        let cycles = [
            TrainingCycle(level: .micro, phase: .build, name: "Trimmed", dateRange: day(0)...day(3), parentID: mesoID),
            TrainingCycle(level: .micro, phase: .recovery, name: "Recovery", dateRange: day(4)...day(13), parentID: mesoID),
        ]
        // 4 days at 100 = 400 total; 10 days at 90 = 900 total. Per day the recovery is only 10% lighter.
        let metrics = (0...3).map { FitnessMetrics(day: day($0), load: 100, ctl: 50, atl: 50, tsb: 0, monotony: 1, strain: 100, isProjected: false, isWarmingUp: false) }
            + (4...13).map { FitnessMetrics(day: day($0), load: 90, ctl: 50, atl: 50, tsb: 0, monotony: 1, strain: 90, isProjected: false, isWarmingUp: false) }
        let finding = evaluator.evaluate(metrics, races: [], cycles: cycles).findings.first { $0.rule == .recoveryMicro }
        #expect(finding != nil)
        #expect(abs((finding?.value ?? 0) - 0.9) < 1e-9)
    }

    @Test("guardrails stored with the micro-count threshold decode as 7-day micros")
    func legacyGuardrailsDecode() throws {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(PlanGuardrails())) as! [String: Any]
        json["maxMicrosWithoutRecovery"] = 4
        json.removeValue(forKey: "maxDaysWithoutRecovery")
        let decoded = try JSONDecoder().decode(PlanGuardrails.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.maxDaysWithoutRecovery == 28)
        #expect(try JSONDecoder().decode(PlanGuardrails.self, from: JSONEncoder().encode(decoded)) == decoded)
    }
}
