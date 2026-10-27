import Foundation
import Testing
@testable import TrainingCore

/// Pins the triphasic numbers (MVP5-137, set with the user on 2026-10-22) so a change to one is a
/// deliberate, visible edit. The reasons are in `docs/design/triphasic-design.md` §10.
@Suite("Triphasic numbers")
struct TriphasicNumbersTests {
    private let evaluator = PlanEvaluator()
    private let paradigm = TrainingParadigm.triphasic

    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    private func findings(_ sessions: [PlanSession], length: Int = 7, phase: CyclePhase) -> [PlanFinding] {
        let micro = TrainingCycle(level: .micro, phase: phase, loadRole: .build, name: "Micro", dateRange: day(0)...day(length - 1), parentID: UUID())
        return evaluator.evaluate([], races: [], cycles: [micro], sessions: sessions, paradigm: paradigm).findings.filter { $0.rule != .longestRun }
    }

    private func session(_ offset: Int, _ intensity: IntensityCategory, speed: SpeedLevel = .slow, minutes: Double) -> PlanSession {
        PlanSession(day: day(offset), seconds: minutes * 60, intensity: intensity, speed: speed)
    }

    @Test("the numbers: per-phase mixes and tolerances, 2 days between hard sessions, no per-micro limit")
    func values() {
        #expect(paradigm.phaseMixes[.conditioning] == IntensityMix(intensityShares: [.medium: 0, .high: 0], speedShares: [.moderate: 0, .fast: 0, .max: 0], tolerance: 0.05))
        #expect(paradigm.phaseMixes[.base] == IntensityMix(intensityShares: [.medium: 0, .high: 0], speedShares: [.moderate: 0, .fast: 0], tolerance: 0.05))
        #expect(paradigm.phaseMixes[.structural] == IntensityMix(intensityShares: [.medium: 0, .high: 0.10], speedShares: [.moderate: 0, .fast: 0.10], tolerance: 0.10))
        let keyWorkouts = IntensityMix(intensityShares: [.medium: 0.25, .high: 0.25], speedShares: [.moderate: 0.25, .fast: 0.25], tolerance: 0.25)
        #expect(paradigm.phaseMixes[.specific] == keyWorkouts)
        #expect(paradigm.phaseMixes[.taper] == keyWorkouts)
        #expect(paradigm.defaultMix == nil)
        #expect(paradigm.minDaysBetweenHardSessions == 2)
        #expect(paradigm.maxHardSessionsPerMicro.isEmpty)
        #expect(paradigm.hardIntensity == .high && paradigm.hardSpeed == .max)
        #expect(paradigm.spacesLongRunsAsHard)
    }

    /// 100 planned minutes, `minutes` of them in a session with the given intensity and speed, the rest easy.
    private func shares(_ minutes: Double, intensity: IntensityCategory, speed: SpeedLevel, phase: CyclePhase) -> [PlanFinding] {
        findings([session(0, .low, minutes: 100 - minutes), session(3, intensity, speed: speed, minutes: minutes)], phase: phase)
    }

    @Test("base: up to 5 % medium, high, moderate or fast (at least 95 % at the extremes); more warns")
    func baseExtremes() {
        #expect(shares(5, intensity: .medium, speed: .moderate, phase: .base).isEmpty)
        #expect(shares(5, intensity: .high, speed: .fast, phase: .base).isEmpty)
        let over = shares(6, intensity: .medium, speed: .moderate, phase: .base)
        #expect(over.contains { $0.subject == "intensity.medium" } && over.contains { $0.subject == "speed.moderate" })
        #expect(shares(6, intensity: .high, speed: .fast, phase: .base).contains { $0.subject == "intensity.high" })
    }

    @Test("base: no ceiling on max-speed time (the skills give none)")
    func baseNoMaxCeiling() {
        #expect(shares(100, intensity: .low, speed: .max, phase: .base).isEmpty)
        #expect(shares(50, intensity: .low, speed: .max, phase: .base).isEmpty)
    }

    @Test("structural: high and fast up to 20 %, medium and moderate up to 10 %; sprints in easy runs unlisted")
    func structural() {
        #expect(shares(20, intensity: .high, speed: .fast, phase: .structural).isEmpty)
        #expect(shares(0, intensity: .high, speed: .fast, phase: .structural).isEmpty)
        let over = shares(21, intensity: .high, speed: .fast, phase: .structural)
        #expect(over.contains { $0.subject == "intensity.high" && $0.severity == .warning } && over.contains { $0.subject == "speed.fast" })
        #expect(shares(10, intensity: .medium, speed: .moderate, phase: .structural).isEmpty)
        let race = shares(11, intensity: .medium, speed: .moderate, phase: .structural)
        #expect(race.contains { $0.subject == "intensity.medium" } && race.contains { $0.subject == "speed.moderate" })
        #expect(shares(100, intensity: .low, speed: .max, phase: .structural).isEmpty)
    }

    @Test("specific and taper: medium, high, moderate and fast each up to 50 %")
    func keyWorkoutPhases() {
        for phase in [CyclePhase.specific, .taper] {
            #expect(shares(50, intensity: .medium, speed: .moderate, phase: phase).isEmpty, "\(phase) at 50 %")
            #expect(shares(50, intensity: .high, speed: .fast, phase: phase).isEmpty, "\(phase) at 50 %")
            let over = shares(51, intensity: .medium, speed: .moderate, phase: phase)
            #expect(over.contains { $0.subject == "intensity.medium" } && over.contains { $0.subject == "speed.moderate" }, "\(phase) at 51 %")
            #expect(shares(51, intensity: .high, speed: .fast, phase: phase).contains { $0.subject == "intensity.high" }, "\(phase) at 51 %")
        }
    }

    @Test("spacing 2 days: Tue to Thu passes, consecutive days are a risk")
    func spacing() {
        func spacing(_ gap: Int) -> [PlanFinding] {
            findings([session(0, .high, minutes: 20), session(gap, .high, minutes: 20)], phase: .specific).filter { $0.rule == .hardSessionSpacing }
        }
        #expect(spacing(2).isEmpty)
        #expect(spacing(3).isEmpty)
        let close = spacing(1)
        #expect(close.count == 1 && close[0].severity == .risk && close[0].value == 1 && close[0].threshold == 2)
    }

    @Test("no per-micro limit: 7, 10 and 14-day micros are never flagged however many hard sessions")
    func noPerMicroLimit() {
        for length in [7, 10, 14] {
            let many = (0..<length / 3 + 1).map { session($0 * 3, .high, speed: .fast, minutes: 5) }
            #expect(!findings(many, length: length, phase: .base).contains { $0.rule == .hardSessionsPerMicro }, "\(length) days")
        }
    }

    @Test("hard means high intensity or max speed: endurance quality and race-pace work are not hard")
    func hardDefinition() {
        #expect(paradigm.isHard(session(0, .low, speed: .max, minutes: 20)))
        #expect(paradigm.isHard(session(0, .high, speed: .fast, minutes: 20)))
        #expect(!paradigm.isHard(session(0, .low, speed: .slow, minutes: 20)))
        #expect(!paradigm.isHard(session(0, .medium, speed: .moderate, minutes: 20)))
    }
}
