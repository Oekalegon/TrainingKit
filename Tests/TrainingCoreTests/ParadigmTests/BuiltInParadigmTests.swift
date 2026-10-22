import Foundation
import Testing
@testable import TrainingCore

@Suite("Built-in paradigms")
struct BuiltInParadigmTests {
    private let evaluator = PlanEvaluator()

    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    private func micro(length: Int, phase: CyclePhase) -> TrainingCycle {
        TrainingCycle(level: .micro, phase: phase, loadRole: .build, name: "Micro", dateRange: day(0)...day(length - 1), parentID: UUID())
    }

    private func session(_ offset: Int, _ intensity: IntensityCategory, speed: SpeedLevel = .slow, minutes: Double) -> PlanSession {
        PlanSession(day: day(offset), seconds: minutes * 60, intensity: intensity, speed: speed)
    }

    private func findings(_ paradigm: TrainingParadigm, _ sessions: [PlanSession], length: Int = 7, phase: CyclePhase) -> [PlanFinding] {
        evaluator.evaluate([], races: [], cycles: [micro(length: length, phase: phase)], sessions: sessions, paradigm: paradigm).findings.filter { $0.rule != .longestRun }
    }

    @Test("the built-in list holds both paradigms, with their phases in order")
    func list() {
        #expect(TrainingParadigm.builtIn == [.polarized8020, .triphasic])
        #expect(TrainingParadigm.polarized8020.phases == [.base, .build, .peak, .taper])
        #expect(TrainingParadigm.triphasic.phases == ["conditioning", "base", "structural", "specific", "taper"])
    }

    @Test("both round-trip through Codable")
    func roundTrip() throws {
        for paradigm in TrainingParadigm.builtIn {
            #expect(try JSONDecoder().decode(TrainingParadigm.self, from: JSONEncoder().encode(paradigm)) == paradigm)
        }
    }

    @Test("polarized: an 80/20 micro passes; easy and very low both count as easy")
    func polarizedPasses() {
        let sessions = [session(0, .veryLow, minutes: 20), session(1, .low, minutes: 52), session(3, .high, minutes: 18)]
        #expect(findings(.polarized8020, sessions, phase: .build).isEmpty)
    }

    @Test("polarized: tempo time and too much hard time warn; a third hard session in 7 days is a risk")
    func polarizedFlags() {
        let tempo = [session(0, .low, minutes: 60), session(2, .medium, minutes: 30)]
        #expect(findings(.polarized8020, tempo, phase: .build).contains { $0.rule == .intensityDistribution && $0.subject == "intensity.medium" })

        let hard = [session(0, .high, minutes: 20), session(2, .high, minutes: 20), session(4, .high, minutes: 20)]
        #expect(findings(.polarized8020, hard, phase: .build).contains { $0.rule == .hardSessionsPerMicro && $0.severity == .risk })
        #expect(!findings(.polarized8020, hard, length: 10, phase: .build).contains { $0.rule == .hardSessionsPerMicro })
    }

    @Test("both built-ins space a long run like a hard session; an ultra-style paradigm can opt out")
    func longRunSpacing() {
        #expect(findings(.polarized8020, [session(0, .high, minutes: 10), session(1, .high, minutes: 10)], phase: .build).contains { $0.rule == .hardSessionSpacing })
        let long = PlanSession(day: day(5), seconds: 9000, intensity: .low, speed: .slow, isLongRun: true)
        let hardNext = session(6, .high, minutes: 20)
        let afterLong = PlanSession(day: day(6), seconds: 9000, intensity: .low, speed: .slow, isLongRun: true)
        for paradigm in TrainingParadigm.builtIn {
            #expect(findings(paradigm, [long, hardNext], phase: .base).contains { $0.rule == .hardSessionSpacing })
            #expect(findings(paradigm, [long, afterLong], phase: .base).contains { $0.rule == .hardSessionSpacing })
        }
        // Long runs do not count towards the per-micro maximum.
        let three = [long, session(2, .high, minutes: 20), session(4, .high, minutes: 20)]
        #expect(!findings(.polarized8020, three, phase: .build).contains { $0.rule == .hardSessionsPerMicro })

        var ultra = TrainingParadigm.polarized8020
        ultra.spacesLongRunsAsHard = false
        #expect(!findings(ultra, [long, afterLong], phase: .build).contains { $0.rule == .hardSessionSpacing })
    }

    @Test("triphasic: base allows slow runs and max-speed sprints but not tempo or fast work")
    func triphasicBase() {
        let sprints = session(1, .low, speed: .max, minutes: 30)
        let easy = session(3, .low, speed: .slow, minutes: 60)
        #expect(findings(.triphasic, [easy, sprints], phase: .base).isEmpty)

        let tempo = session(3, .medium, speed: .moderate, minutes: 30)
        let result = findings(.triphasic, [easy, tempo], phase: .base)
        #expect(result.contains { $0.subject == "intensity.medium" } && result.contains { $0.subject == "speed.moderate" })
    }

    @Test("triphasic: conditioning allows easy slow running only")
    func triphasicConditioning() {
        #expect(findings(.triphasic, [session(0, .low, minutes: 60)], phase: .conditioning).isEmpty)
        #expect(findings(.triphasic, [session(0, .low, minutes: 50), session(2, .low, speed: .max, minutes: 10)], phase: .conditioning).contains { $0.subject == "speed.max" })
    }

    @Test("triphasic: a max-speed easy session is hard for spacing; no per-micro limit")
    func triphasicHard() {
        let sprints = session(0, .low, speed: .max, minutes: 20)
        let close = [sprints, session(1, .high, speed: .fast, minutes: 30)]
        #expect(findings(.triphasic, close, phase: .base).contains { $0.rule == .hardSessionSpacing })

        let many = (0..<5).map { session($0 * 2, .high, speed: .fast, minutes: 30) }
        #expect(!findings(.triphasic, many, length: 14, phase: .structural).contains { $0.rule == .hardSessionsPerMicro })
    }
}
