import Foundation
import Testing
@testable import TrainingCore

@Suite("PlanEvaluator longest-run rule")
struct PlanEvaluatorLongestRunTests {
    let evaluator = PlanEvaluator()

    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    private func run(_ offset: Int, minutes: Double) -> PlanSession {
        PlanSession(day: day(offset), seconds: minutes * 60, intensity: .low, speed: .slow)
    }

    private func findings(_ sessions: [PlanSession], guardrails: PlanGuardrails = PlanGuardrails()) -> [PlanFinding] {
        evaluator.evaluate([], races: [], guardrails: guardrails, sessions: sessions).findings.filter { $0.rule == .longestRun }
    }

    @Test("a run more than 10% over the longest of the previous 28 days is a risk dated at the run")
    func overLimit() {
        let result = findings([run(0, minutes: 100), run(7, minutes: 111)])
        #expect(result.count == 1)
        #expect(result[0].day == day(7) && result[0].severity == .risk)
        #expect(abs(result[0].value - 0.11) < 1e-9 && result[0].threshold == 0.10)
    }

    @Test("exactly 10% over passes; shorter and equal runs pass")
    func boundary() {
        #expect(findings([run(0, minutes: 100), run(7, minutes: 110)]).isEmpty)
        #expect(findings([run(0, minutes: 100), run(7, minutes: 100), run(14, minutes: 60)]).isEmpty)
    }

    @Test("the look-back is 28 days: a run 28 days back counts, 29 days back does not")
    func lookBack() {
        #expect(findings([run(0, minutes: 100), run(28, minutes: 150)]).count == 1)
        #expect(findings([run(0, minutes: 100), run(29, minutes: 150)]).isEmpty)
    }

    @Test("the look-back is a guardrail")
    func lookBackGuardrail() {
        let sessions = [run(0, minutes: 100), run(15, minutes: 150)]
        #expect(findings(sessions).count == 1)
        #expect(findings(sessions, guardrails: PlanGuardrails(longestRunLookBackDays: 14)).isEmpty)
    }

    @Test("the longest previous run is the baseline, not the latest; any type counts")
    func longestIsBaseline() {
        let sessions = [run(0, minutes: 120), run(3, minutes: 30), PlanSession(day: day(10), seconds: 125 * 60, intensity: .high, speed: .fast)]
        #expect(findings(sessions).isEmpty)
        #expect(findings(sessions + [run(12, minutes: 140)]).count == 1)
    }

    @Test("the first run, same-day runs and unsorted input are handled; zero-length sessions are ignored")
    func edges() {
        #expect(findings([run(0, minutes: 200)]).isEmpty)
        #expect(findings([run(0, minutes: 100), run(0, minutes: 200)]).isEmpty) // the same day is not "previous"
        #expect(findings([run(7, minutes: 150), run(0, minutes: 100)]).count == 1)
        #expect(findings([run(0, minutes: 0), run(7, minutes: 100)]).isEmpty)
    }

    @Test("a chain of runs each within the limit of the last is allowed")
    func chain() {
        #expect(findings([run(0, minutes: 100), run(7, minutes: 110), run(14, minutes: 121)]).isEmpty)
    }

    @Test("the limit is a guardrail and a paradigm can override it")
    func overridable() {
        let sessions = [run(0, minutes: 100), run(7, minutes: 120)]
        #expect(findings(sessions).count == 1)
        #expect(findings(sessions, guardrails: PlanGuardrails(maxLongestRunIncreaseFraction: 0.25)).isEmpty)
        let paradigm = TrainingParadigm(name: "x", guardrailOverrides: .init(maxLongestRunIncreaseFraction: 0.25))
        #expect(evaluator.evaluate([], races: [], sessions: sessions, paradigm: paradigm).findings.isEmpty)
    }

    @Test("the window is calendar days across a daylight-saving change, and the rule makes a plan unacceptable")
    func dstAndAcceptability() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        let end = calendar.date(byAdding: .day, value: 28, to: start)! // spans the 29 March change
        let sessions = [PlanSession(day: start, seconds: 6000, intensity: .low, speed: .slow), PlanSession(day: end, seconds: 9000, intensity: .low, speed: .slow)]
        let evaluation = evaluator.evaluate([], races: [], sessions: sessions)
        #expect(evaluation.findings.count == 1 && !evaluation.isAcceptable)
    }

    @Test("guardrails stored before the longest-run limit decode with its default; the removed key is ignored")
    func legacyGuardrails() throws {
        let data = Data(#"{"maxMonotony":2.5,"maxBuildProgressionFraction":0.2}"#.utf8)
        let decoded = try JSONDecoder().decode(PlanGuardrails.self, from: data)
        #expect(decoded.maxMonotony == 2.5)
        #expect(decoded.maxLongestRunIncreaseFraction == 0.10)
        #expect(decoded.minAcceptableTSB == PlanGuardrails().minAcceptableTSB)
        #expect(try JSONDecoder().decode(PlanGuardrails.self, from: JSONEncoder().encode(decoded)) == decoded)
    }
}
