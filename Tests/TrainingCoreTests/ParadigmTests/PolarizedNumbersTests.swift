import Foundation
import Testing
@testable import TrainingCore

/// Pins the 80/20 polarized numbers (MVP5-136) so a change to one is a deliberate, visible edit.
@Suite("Polarized 80/20 numbers")
struct PolarizedNumbersTests {
    private let evaluator = PlanEvaluator()
    private let paradigm = TrainingParadigm.polarized8020

    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    private func findings(_ sessions: [PlanSession], length: Int = 7, phase: CyclePhase = .build) -> [PlanFinding] {
        let micro = TrainingCycle(level: .micro, phase: phase, loadRole: .build, name: "Micro", dateRange: day(0)...day(length - 1), parentID: UUID())
        return evaluator.evaluate([], races: [], cycles: [micro], sessions: sessions, paradigm: paradigm).findings
    }

    private func session(_ offset: Int, _ intensity: IntensityCategory, minutes: Double) -> PlanSession {
        PlanSession(day: day(offset), seconds: minutes * 60, intensity: intensity, speed: .slow)
    }

    /// `count` hard sessions, 2 days apart so only the per-micro limit can fire.
    private func hardSessions(_ count: Int) -> [PlanSession] {
        (0..<count).map { session($0 * 2, .high, minutes: 20) }
    }

    @Test("the numbers: 0.2 high, 0 medium, tolerance 0.05, 2 days apart, 2/3/4 hard per micro, long runs spaced as hard")
    func values() {
        let mix = paradigm.defaultMix
        #expect(mix?.intensityShares == [.high: 0.2, .medium: 0])
        #expect(mix?.tolerance == 0.05)
        #expect(paradigm.minDaysBetweenHardSessions == 2)
        #expect(paradigm.maxHardSessionsPerMicro == [7: 2, 10: 3, 14: 4])
        #expect(paradigm.spacesLongRunsAsHard)
    }

    @Test("the mix is the same in every phase (no per-phase variants)")
    func samePhases() {
        #expect(paradigm.phaseMixes.isEmpty)
        let sessions = [session(0, .low, minutes: 70), session(3, .high, minutes: 30)]
        for phase in paradigm.phases {
            #expect(findings(sessions, phase: phase).contains { $0.rule == .intensityDistribution })
        }
    }

    @Test("tolerance 0.05: high up to 25 % passes, above warns")
    func highTolerance() {
        let atLimit = [session(0, .low, minutes: 75), session(3, .high, minutes: 25)]
        #expect(findings(atLimit).isEmpty)
        let over = [session(0, .low, minutes: 74), session(3, .high, minutes: 26)]
        #expect(findings(over).contains { $0.subject == "intensity.high" && $0.severity == .warning })
        let under = [session(0, .low, minutes: 85), session(3, .high, minutes: 15)]
        #expect(findings(under).isEmpty)
        let tooLittle = [session(0, .low, minutes: 86), session(3, .high, minutes: 14)]
        #expect(findings(tooLittle).contains { $0.subject == "intensity.high" })
    }

    @Test("medium target 0: up to 5 % medium passes, above warns")
    func mediumTarget() {
        let atLimit = [session(0, .low, minutes: 75), session(2, .medium, minutes: 5), session(4, .high, minutes: 20)]
        #expect(findings(atLimit).isEmpty)
        let over = [session(0, .low, minutes: 74), session(2, .medium, minutes: 6), session(4, .high, minutes: 20)]
        #expect(findings(over).contains { $0.subject == "intensity.medium" })
    }

    @Test("hard sessions per micro: 2 in 7 days, 3 in 10, 4 in 14; one more is a risk")
    func hardPerMicro() {
        for (length, maximum) in [(7, 2), (10, 3), (14, 4)] {
            #expect(!findings(hardSessions(maximum), length: length).contains { $0.rule == .hardSessionsPerMicro }, "\(maximum) in \(length) days")
            let over = findings(hardSessions(maximum + 1), length: length).filter { $0.rule == .hardSessionsPerMicro }
            #expect(over.count == 1 && over[0].severity == .risk && over[0].value == Double(maximum + 1) && over[0].threshold == Double(maximum), "\(maximum + 1) in \(length) days")
        }
    }

    @Test("hard-session spacing 2 days: Tue to Thu passes, consecutive days is a risk")
    func spacing() {
        #expect(!findings([session(0, .high, minutes: 20), session(2, .high, minutes: 20)]).contains { $0.rule == .hardSessionSpacing })
        let close = findings([session(0, .high, minutes: 20), session(1, .high, minutes: 20)]).filter { $0.rule == .hardSessionSpacing }
        #expect(close.count == 1 && close[0].severity == .risk && close[0].threshold == 2)
    }
}
