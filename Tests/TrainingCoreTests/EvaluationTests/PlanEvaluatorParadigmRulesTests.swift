import Foundation
import Testing
@testable import TrainingCore

@Suite("PlanEvaluator paradigm rules")
struct PlanEvaluatorParadigmRulesTests {
    let evaluator = PlanEvaluator()

    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    private func micro(start: Int, length: Int, phase: CyclePhase = .build) -> TrainingCycle {
        TrainingCycle(level: .micro, phase: phase, loadRole: .build, name: "Micro", dateRange: day(start)...day(start + length - 1), parentID: UUID())
    }

    private func session(_ offset: Int, _ intensity: IntensityCategory = .high, speed: SpeedLevel = .fast, minutes: Double = 60) -> PlanSession {
        PlanSession(day: day(offset), seconds: minutes * 60, intensity: intensity, speed: speed)
    }

    private func findings(_ rule: PlanRule, sessions: [PlanSession], cycles: [TrainingCycle] = [], paradigm: TrainingParadigm?) -> [PlanFinding] {
        evaluator.evaluate([], races: [], cycles: cycles, sessions: sessions, paradigm: paradigm).findings.filter { $0.rule == rule }
    }

    // MARK: - No paradigm

    @Test("without a paradigm no paradigm rule runs, whatever the sessions")
    func noParadigm() {
        let sessions = (0..<7).map { session($0) }
        let evaluation = evaluator.evaluate([], races: [], cycles: [micro(start: 0, length: 7)], sessions: sessions)
        #expect(evaluation.findings.isEmpty)
    }

    @Test("a paradigm with the rules unset adds no findings")
    func emptyParadigm() {
        let sessions = (0..<7).map { session($0) }
        #expect(evaluator.evaluate([], races: [], cycles: [micro(start: 0, length: 7)], sessions: sessions, paradigm: TrainingParadigm(name: "x")).findings.isEmpty)
    }

    @Test("a paradigm's overrides are applied to the guardrails")
    func overridesReachRules() {
        let metrics = (0..<3).map {
            FitnessMetrics(day: day($0), load: 50, ctl: 50, atl: 50, tsb: -40, monotony: 1, strain: 1, isProjected: true, isWarmingUp: false)
        }
        #expect(evaluator.evaluate(metrics, races: []).findings.contains { $0.rule == .tsbBand })
        let paradigm = TrainingParadigm(name: "x", guardrailOverrides: .init(minAcceptableTSB: -50))
        #expect(!evaluator.evaluate(metrics, races: [], paradigm: paradigm).findings.contains { $0.rule == .tsbBand })
    }

    // MARK: - Hard-session spacing

    @Test("spacing: the boundary passes, one day less is a risk dated at the later session; same day fails")
    func spacing() {
        let paradigm = TrainingParadigm(name: "x", minDaysBetweenHardSessions: 2)
        #expect(findings(.hardSessionSpacing, sessions: [session(0), session(2), session(4)], paradigm: paradigm).isEmpty)

        let close = findings(.hardSessionSpacing, sessions: [session(0), session(1)], paradigm: paradigm)
        #expect(close.count == 1)
        #expect(close[0].day == day(1) && close[0].value == 1 && close[0].threshold == 2 && close[0].severity == .risk)

        #expect(findings(.hardSessionSpacing, sessions: [session(3), session(3)], paradigm: paradigm).count == 1)
    }

    @Test("spacing ignores easy sessions and works without cycles; sessions need not be sorted")
    func spacingIgnoresEasy() {
        let paradigm = TrainingParadigm(name: "x", minDaysBetweenHardSessions: 2)
        let sessions = [session(3), session(2, .low, speed: .slow), session(0)]
        #expect(findings(.hardSessionSpacing, sessions: sessions, paradigm: paradigm).isEmpty)
        #expect(findings(.hardSessionSpacing, sessions: [session(1), session(0)], paradigm: paradigm).count == 1)
    }

    @Test("spacing counts a max-speed easy session as hard only when the paradigm sets hardSpeed")
    func spacingWithSpeed() {
        let sprints = session(1, .low, speed: .max)
        let sessions = [session(0), sprints]
        #expect(findings(.hardSessionSpacing, sessions: sessions, paradigm: TrainingParadigm(name: "x", minDaysBetweenHardSessions: 2)).isEmpty)
        #expect(findings(.hardSessionSpacing, sessions: sessions, paradigm: TrainingParadigm(name: "x", hardSpeed: .max, minDaysBetweenHardSessions: 2)).count == 1)
    }

    @Test("spacing does not change across a daylight-saving day")
    func spacingAcrossDST() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 28))!
        let later = calendar.date(byAdding: .day, value: 2, to: start)! // 47 hours later
        let sessions = [PlanSession(day: start, seconds: 3600, intensity: .high, speed: .fast), PlanSession(day: later, seconds: 3600, intensity: .high, speed: .fast)]
        #expect(findings(.hardSessionSpacing, sessions: sessions, paradigm: TrainingParadigm(name: "x", minDaysBetweenHardSessions: 2)).isEmpty)
    }

    // MARK: - Hard sessions per micro

    @Test("per micro: limits by length for 7-, 10- and 14-day micros; boundary passes, one more is a risk")
    func perMicro() {
        let paradigm = TrainingParadigm(name: "x", maxHardSessionsPerMicro: [7: 2, 10: 3, 14: 4])
        for (length, limit) in [(7, 2), (10, 3), (14, 4)] {
            let cycles = [micro(start: 100, length: length)]
            let atLimit = (0..<limit).map { session(100 + $0) }
            #expect(findings(.hardSessionsPerMicro, sessions: atLimit, cycles: cycles, paradigm: paradigm).isEmpty)

            let over = atLimit + [session(100 + limit)]
            let result = findings(.hardSessionsPerMicro, sessions: over, cycles: cycles, paradigm: paradigm)
            #expect(result.count == 1)
            #expect(result[0].day == day(100) && result[0].value == Double(limit + 1) && result[0].threshold == Double(limit) && result[0].severity == .risk)
        }
    }

    @Test("per micro: sessions outside the micro, easy sessions and unlisted lengths are not counted")
    func perMicroScope() {
        let paradigm = TrainingParadigm(name: "x", maxHardSessionsPerMicro: [7: 1])
        let cycles = [micro(start: 0, length: 7), micro(start: 7, length: 10)]
        let sessions = [session(0), session(1, .low, speed: .slow), session(7), session(8), session(9)]
        #expect(findings(.hardSessionsPerMicro, sessions: sessions, cycles: cycles, paradigm: paradigm).isEmpty)
        #expect(findings(.hardSessionsPerMicro, sessions: sessions, paradigm: paradigm).isEmpty) // no cycles
    }

    // MARK: - Intensity distribution

    private let polarized = IntensityMix(intensityShares: [.low: 0.8, .high: 0.2], tolerance: 0.05)

    @Test("distribution: 80/20 within tolerance passes, boundary passes, beyond tolerance warns")
    func distribution() {
        let paradigm = TrainingParadigm(name: "x", defaultMix: polarized)
        let cycles = [micro(start: 0, length: 7)]
        // 72 min easy + 18 min hard = 80/20.
        let exact = [session(0, .low, speed: .slow, minutes: 72), session(2, .high, minutes: 18)]
        #expect(findings(.intensityDistribution, sessions: exact, cycles: cycles, paradigm: paradigm).isEmpty)

        // Hard share exactly 25 % (target 20 % + 5 points): passes.
        let boundary = [session(0, .low, speed: .slow, minutes: 75), session(2, .high, minutes: 25)]
        #expect(findings(.intensityDistribution, sessions: boundary, cycles: cycles, paradigm: paradigm).isEmpty)

        // Hard share 30 %: both categories are out of tolerance.
        let heavy = [session(0, .low, speed: .slow, minutes: 70), session(2, .high, minutes: 30)]
        let result = findings(.intensityDistribution, sessions: heavy, cycles: cycles, paradigm: paradigm)
        #expect(result.count == 2)
        #expect(result.allSatisfy { $0.severity == .warning && $0.day == day(0) })
        let high = result.first { $0.subject == "intensity.high" }
        #expect(high != nil && abs(high!.value - 0.3) < 1e-9 && abs(high!.threshold - 0.25) < 1e-9)
        #expect(result.contains { $0.subject == "intensity.low" })
    }

    @Test("distribution: the phase's mix wins over the default; a phase with neither is skipped")
    func distributionPerPhase() {
        let baseMix = IntensityMix(intensityShares: [.high: 0, .medium: 0])
        let paradigm = TrainingParadigm(name: "x", defaultMix: polarized, phaseMixes: ["base": baseMix])
        let sessions = [session(0, .low, speed: .slow, minutes: 50), session(2, .high, minutes: 10)]
        let base = findings(.intensityDistribution, sessions: sessions, cycles: [micro(start: 0, length: 7, phase: "base")], paradigm: paradigm)
        #expect(base.count == 1 && abs(base[0].value - 10.0 / 60) < 1e-9)

        let noMix = TrainingParadigm(name: "x", phaseMixes: ["base": baseMix])
        #expect(findings(.intensityDistribution, sessions: sessions, cycles: [micro(start: 0, length: 7, phase: .build)], paradigm: noMix).isEmpty)
    }

    @Test("distribution: hill sprints are easy time by intensity but max by speed, in 10- and 14-day micros")
    func distributionSpeed() {
        let mix = IntensityMix(intensityShares: [.low: 1.0], speedShares: [.max: 0.0, .slow: 0.9], tolerance: 0.1)
        let paradigm = TrainingParadigm(name: "x", defaultMix: mix)
        let sprints = session(1, .low, speed: .max, minutes: 30)
        let easy = session(3, .low, speed: .slow, minutes: 30)
        for length in [10, 14] {
            let cycles = [micro(start: 0, length: length)]
            #expect(findings(.intensityDistribution, sessions: [easy, easy], cycles: cycles, paradigm: paradigm).isEmpty)
            // Intensity is all low (passes); half the time is max speed, and the slow share is 50 %.
            #expect(findings(.intensityDistribution, sessions: [sprints, easy], cycles: cycles, paradigm: paradigm).count == 2)
        }
    }

    @Test("distribution: a negative tolerance is treated as zero; speed findings name the level")
    func distributionTolerance() {
        let mix = IntensityMix(intensityShares: [.low: 0.5], speedShares: [.max: 0], tolerance: -0.2)
        let paradigm = TrainingParadigm(name: "x", defaultMix: mix)
        let sessions = [session(0, .low, speed: .max, minutes: 30), session(2, .high, speed: .fast, minutes: 30)]
        let result = findings(.intensityDistribution, sessions: sessions, cycles: [micro(start: 0, length: 7)], paradigm: paradigm)
        #expect(result.map(\.subject) == ["speed.max"]) // low is exactly 0.5; tolerance clamps to 0
    }

    @Test("distribution: a micro with no sessions or no planned time is skipped")
    func distributionEmpty() {
        let paradigm = TrainingParadigm(name: "x", defaultMix: polarized)
        let cycles = [micro(start: 0, length: 7)]
        #expect(findings(.intensityDistribution, sessions: [], cycles: cycles, paradigm: paradigm).isEmpty)
        #expect(findings(.intensityDistribution, sessions: [session(0, .low, minutes: 0)], cycles: cycles, paradigm: paradigm).isEmpty)
    }

    @Test("only risks make a plan unacceptable: distribution alone stays acceptable, spacing does not")
    func acceptability() {
        let cycles = [micro(start: 0, length: 7)]
        let distribution = TrainingParadigm(name: "x", defaultMix: polarized)
        let heavy = [session(0, .high), session(4, .high)]
        let evaluation = evaluator.evaluate([], races: [], cycles: cycles, sessions: heavy, paradigm: distribution)
        #expect(!evaluation.findings.isEmpty && evaluation.isAcceptable)

        let spacing = TrainingParadigm(name: "x", minDaysBetweenHardSessions: 7)
        #expect(!evaluator.evaluate([], races: [], sessions: heavy, paradigm: spacing).isAcceptable)
    }
}
