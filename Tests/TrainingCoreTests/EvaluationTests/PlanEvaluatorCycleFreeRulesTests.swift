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

    // MARK: - TSB band

    @Test("TSB below the min fires risk; above the max fires warning, not risk")
    func tsbBandBounds() {
        let metrics = [
            metric(0, tsb: -31), // below the default -30 min -> risk
            metric(1, tsb: 26), // above the default 25 max -> warning
            metric(2, tsb: 0), // within band
        ]

        let evaluation = evaluator.evaluate(metrics, races: [])

        let findings = evaluation.findings.filter { $0.rule == .tsbBand }
        #expect(findings.count == 2)
        #expect(findings.first { $0.day == day(0) }?.severity == .risk)
        #expect(findings.first { $0.day == day(1) }?.severity == .warning)
        #expect(!findings.contains { $0.day == day(2) })
    }

    @Test("TSB exactly at the min or max threshold doesn't fire — comparisons are strict")
    func tsbBandExactlyAtThresholdDoesNotFire() {
        let metrics = [
            metric(0, tsb: -30), // exactly the default min
            metric(1, tsb: 25), // exactly the default max
        ]

        let evaluation = evaluator.evaluate(metrics, races: [])

        #expect(!evaluation.findings.contains { $0.rule == .tsbBand })
    }

    @Test("a TSB band breach during warmup doesn't fire, even though the raw TSB exceeds the bounds")
    func tsbBandSkipsWarmingUpDays() {
        let metrics = [metric(0, tsb: -50, isWarmingUp: true)] // would be risk if not warming up

        let evaluation = evaluator.evaluate(metrics, races: [])

        #expect(!evaluation.findings.contains { $0.rule == .tsbBand })
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

    @Test("race-day TSB below the minimum or above the maximum fires warning, not risk; within range doesn't")
    func raceDayTSBBounds() {
        let metrics = [
            metric(0, tsb: 2), // below min (5)
            metric(1, tsb: 30), // above max (25)
            metric(2, tsb: 15), // within range
        ]
        let races = [
            Race(name: "Undertapered", date: day(0), priority: .primary, distanceMeters: 10_000),
            Race(name: "Overtapered", date: day(1), priority: .primary, distanceMeters: 10_000),
            Race(name: "Just right", date: day(2), priority: .primary, distanceMeters: 10_000),
        ]

        let evaluation = evaluator.evaluate(metrics, races: races)

        let findings = evaluation.findings.filter { $0.rule == .raceDayTSB }
        #expect(findings.count == 2)
        #expect(findings.contains { $0.day == day(0) && $0.severity == .warning })
        #expect(findings.contains { $0.day == day(1) && $0.severity == .warning })
    }

    @Test("race-day TSB exactly at the min or max threshold doesn't fire — comparisons are strict")
    func raceDayTSBExactlyAtThresholdDoesNotFire() {
        let metrics = [
            metric(0, tsb: 5), // exactly the default min
            metric(1, tsb: 25), // exactly the default max
        ]
        let races = [
            Race(name: "Exactly at min", date: day(0), priority: .primary, distanceMeters: 10_000),
            Race(name: "Exactly at max", date: day(1), priority: .primary, distanceMeters: 10_000),
        ]

        let evaluation = evaluator.evaluate(metrics, races: races)

        #expect(!evaluation.findings.contains { $0.rule == .raceDayTSB })
    }

    @Test("a race date with no matching metrics day is skipped")
    func raceDayTSBSkipsUnmatchedDate() {
        let metrics = [metric(0, tsb: 15)]
        let races = [Race(name: "Far future race", date: day(100), priority: .primary, distanceMeters: 10_000)]

        let evaluation = evaluator.evaluate(metrics, races: races)

        #expect(!evaluation.findings.contains { $0.rule == .raceDayTSB })
    }

    // MARK: - isAcceptable

    @Test("isAcceptable is false with any risk finding and true otherwise")
    func isAcceptable() {
        let risky = PlanEvaluation(findings: [PlanFinding(day: day(0), rule: .monotony, severity: .risk, value: 3, threshold: 2)])
        let warningOnly = PlanEvaluation(findings: [PlanFinding(day: day(0), rule: .tsbBand, severity: .warning, value: 30, threshold: 25)])
        let clean = PlanEvaluation(findings: [])

        #expect(risky.isAcceptable == false)
        #expect(warningOnly.isAcceptable == true)
        #expect(clean.isAcceptable == true)
    }

    // MARK: - Stored guardrails

    @Test("guardrails stored with the removed thresholds' keys still decode, ignoring them")
    func storedGuardrailsWithRemovedKeysDecode() throws {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(PlanGuardrails())) as! [String: Any]
        for key in ["maxCTLRampPerWeek", "maxATLtoCTLRatio", "minATLtoCTLRatio", "minCTLForRatioCheck", "recoveryLoadFraction", "minCTLGainPerMeso", "maxMicrosWithoutRecovery", "maxTaperCTLDropFraction"] {
            json[key] = 1
        }
        let decoded = try JSONDecoder().decode(PlanGuardrails.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded == PlanGuardrails())
    }
}
