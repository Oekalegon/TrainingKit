import Foundation
import Testing
@testable import TrainingCore

@Suite("PlanEvaluator cycle-free rules")
struct PlanEvaluatorCycleFreeRulesTests {
    let evaluator = PlanEvaluator()

    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    private func metric(
        _ offset: Int,
        ctl: Double = 50,
        atl: Double = 50,
        tsb: Double = 0,
        monotony: Double = 1.0,
        strain: Double = 100,
        load: Double = 50,
        isWarmingUp: Bool = false
    ) -> FitnessMetrics {
        FitnessMetrics(day: day(offset), load: load, ctl: ctl, atl: atl, tsb: tsb, monotony: monotony, strain: strain, isProjected: false, isWarmingUp: isWarmingUp)
    }

    // MARK: - CTL ramp

    @Test("a CTL ramp over the threshold fires risk on the day it's measured")
    func ctlRampExceeded() {
        var metrics = (0..<8).map { metric($0, ctl: 50) }
        metrics[7] = metric(7, ctl: 57) // +7 over 7 days, threshold is 6

        let evaluation = evaluator.evaluate(metrics, races: [])

        let finding = evaluation.findings.first { $0.rule == .ctlRamp }
        #expect(finding != nil)
        #expect(finding?.severity == .risk)
        #expect(finding?.day == day(7))
        #expect(abs((finding?.value ?? 0) - 7) < 1e-9)
        #expect(finding?.threshold == 6)
    }

    @Test("a CTL ramp within the threshold doesn't fire, and days without 7 days of history are skipped")
    func ctlRampWithinThreshold() {
        // Only day 7 has a day-7 predecessor to compare against; its ramp is 3.5, under the 6 threshold.
        let metrics = (0..<8).map { metric($0, ctl: 50 + Double($0) * 0.5) }

        let evaluation = evaluator.evaluate(metrics, races: [])

        #expect(!evaluation.findings.contains { $0.rule == .ctlRamp })
    }

    @Test("a CTL ramp during warmup doesn't fire, even though the raw ramp exceeds the threshold")
    func ctlRampSkipsWarmingUpDays() {
        var metrics = (0..<8).map { metric($0, ctl: 50, isWarmingUp: true) }
        metrics[7] = metric(7, ctl: 57, isWarmingUp: true) // would be a risk finding if not warming up

        let evaluation = evaluator.evaluate(metrics, races: [])

        #expect(!evaluation.findings.contains { $0.rule == .ctlRamp })
    }

    // MARK: - ATL/CTL ratio

    @Test("ATL/CTL above the max fires risk; below the min fires warning, not risk")
    func atlToCTLRatioBounds() {
        let metrics = [
            metric(0, ctl: 50, atl: 80), // ratio 1.6 > 1.4 max
            metric(1, ctl: 50, atl: 20), // ratio 0.4 < 0.7 min
            metric(2, ctl: 50, atl: 50), // ratio 1.0, within band
        ]

        let evaluation = evaluator.evaluate(metrics, races: [])

        let findings = evaluation.findings.filter { $0.rule == .atlToCTLRatio }
        #expect(findings.count == 2)
        #expect(findings.first { $0.day == day(0) }?.severity == .risk)
        #expect(findings.first { $0.day == day(1) }?.severity == .warning)
        #expect(!findings.contains { $0.day == day(2) })
    }

    @Test("ATL/CTL exactly at the max or min threshold doesn't fire — comparisons are strict")
    func atlToCTLRatioExactlyAtThresholdDoesNotFire() {
        // Guards against an accidental `>=`/`<=` flip: the guardrail's own defaults (1.4 max,
        // 0.7 min) describe a band, and a ratio sitting exactly on its edge is documented as
        // still within it, not already over.
        let metrics = [
            metric(0, ctl: 50, atl: 70), // ratio exactly 1.4 (the default max)
            metric(1, ctl: 50, atl: 35), // ratio exactly 0.7 (the default min)
        ]

        let evaluation = evaluator.evaluate(metrics, races: [])

        #expect(!evaluation.findings.contains { $0.rule == .atlToCTLRatio })
    }

    @Test("a zero CTL day is skipped rather than dividing by zero")
    func atlToCTLRatioSkipsZeroCTL() {
        let metrics = [metric(0, ctl: 0, atl: 10)]

        let evaluation = evaluator.evaluate(metrics, races: [])

        #expect(!evaluation.findings.contains { $0.rule == .atlToCTLRatio })
    }

    @Test("an ATL/CTL ratio during warmup doesn't fire, even though the raw ratio exceeds the max")
    func atlToCTLRatioSkipsWarmingUpDays() {
        let metrics = [metric(0, ctl: 50, atl: 80, isWarmingUp: true)] // would be risk if not warming up

        let evaluation = evaluator.evaluate(metrics, races: [])

        #expect(!evaluation.findings.contains { $0.rule == .atlToCTLRatio })
    }

    // MARK: - Duplicate days

    @Test("two metrics entries sharing a day don't crash evaluate")
    func duplicateDayDoesNotCrash() {
        let metrics = [
            metric(0, ctl: 40),
            FitnessMetrics(day: day(0), load: 60, ctl: 41, atl: 42, tsb: 0, monotony: 1, strain: 50, isProjected: false, isWarmingUp: false),
        ]

        let evaluation = evaluator.evaluate(metrics, races: [])

        #expect(evaluation.findings.isEmpty)
    }

    // MARK: - Monotony

    @Test("monotony above the max fires risk; .nan (a flat/rest week) never fires")
    func monotonyRule() {
        let metrics = [
            metric(0, monotony: 2.5),
            metric(1, monotony: .nan),
            metric(2, monotony: 1.0),
        ]

        let evaluation = evaluator.evaluate(metrics, races: [])

        let findings = evaluation.findings.filter { $0.rule == .monotony }
        #expect(findings.count == 1)
        #expect(findings.first?.day == day(0))
        #expect(findings.first?.severity == .risk)
    }

    @Test("monotony exactly at the max doesn't fire — the comparison is strict")
    func monotonyExactlyAtThresholdDoesNotFire() {
        let metrics = [metric(0, monotony: 2.0)] // exactly the default max

        let evaluation = evaluator.evaluate(metrics, races: [])

        #expect(!evaluation.findings.contains { $0.rule == .monotony })
    }

    // MARK: - Strain

    @Test("a strain spike above the trailing-window percentile fires risk")
    func strainSpikeFiresRisk() {
        // 20 days of flat strain, then one big spike — the spike is at the 100th percentile of its
        // own trailing window, comfortably above the 0.95 default.
        var metrics = (0..<21).map { metric($0, strain: 100) }
        metrics[20] = metric(20, strain: 1000)

        let evaluation = evaluator.evaluate(metrics, races: [])

        let findings = evaluation.findings.filter { $0.rule == .strain }
        #expect(findings.count == 1)
        #expect(findings.first?.day == day(20))
    }

    @Test("strain is skipped without enough trailing history")
    func strainSkippedWithoutHistory() {
        let metrics = (0..<5).map { metric($0, strain: 100 + Double($0) * 1000) }

        let evaluation = evaluator.evaluate(metrics, races: [])

        #expect(!evaluation.findings.contains { $0.rule == .strain })
    }

    // MARK: - Race-day TSB

    @Test("race-day TSB below the minimum or above the maximum fires risk; within range doesn't")
    func raceDayTSBBounds() {
        let metrics = [
            metric(0, tsb: 2), // below min (5)
            metric(1, tsb: 30), // above max (25)
            metric(2, tsb: 15), // within range
        ]
        let races = [
            Race(name: "Undertapered", date: day(0), priority: .a),
            Race(name: "Overtapered", date: day(1), priority: .a),
            Race(name: "Just right", date: day(2), priority: .a),
        ]

        let evaluation = evaluator.evaluate(metrics, races: races)

        let findings = evaluation.findings.filter { $0.rule == .raceDayTSB }
        #expect(findings.count == 2)
        #expect(findings.contains { $0.day == day(0) && $0.severity == .risk })
        #expect(findings.contains { $0.day == day(1) && $0.severity == .risk })
    }

    @Test("race-day TSB exactly at the min or max threshold doesn't fire — comparisons are strict")
    func raceDayTSBExactlyAtThresholdDoesNotFire() {
        let metrics = [
            metric(0, tsb: 5), // exactly the default min
            metric(1, tsb: 25), // exactly the default max
        ]
        let races = [
            Race(name: "Exactly at min", date: day(0), priority: .a),
            Race(name: "Exactly at max", date: day(1), priority: .a),
        ]

        let evaluation = evaluator.evaluate(metrics, races: races)

        #expect(!evaluation.findings.contains { $0.rule == .raceDayTSB })
    }

    @Test("a race date with no matching metrics day is skipped")
    func raceDayTSBSkipsUnmatchedDate() {
        let metrics = [metric(0, tsb: 15)]
        let races = [Race(name: "Far future race", date: day(100), priority: .a)]

        let evaluation = evaluator.evaluate(metrics, races: races)

        #expect(!evaluation.findings.contains { $0.rule == .raceDayTSB })
    }

    // MARK: - isAcceptable

    @Test("isAcceptable is false with any risk finding and true otherwise")
    func isAcceptable() {
        let risky = PlanEvaluation(findings: [PlanFinding(day: day(0), rule: .monotony, severity: .risk, value: 3, threshold: 2)])
        let warningOnly = PlanEvaluation(findings: [PlanFinding(day: day(0), rule: .atlToCTLRatio, severity: .warning, value: 0.5, threshold: 0.7)])
        let clean = PlanEvaluation(findings: [])

        #expect(risky.isAcceptable == false)
        #expect(warningOnly.isAcceptable == true)
        #expect(clean.isAcceptable == true)
    }
}
