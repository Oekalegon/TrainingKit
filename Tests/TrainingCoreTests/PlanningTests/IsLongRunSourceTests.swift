import Foundation
import Testing
@testable import TrainingCore

@Suite("Where PlanSession.isLongRun comes from (MVP5-139)")
struct IsLongRunSourceTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
        return calendar
    }

    private var monday: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 5))! }
    private func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: monday)! }
    private let athlete = AthleteProfile.fixture()
    private let classifier = PlannedIntensityClassifier()

    private func run(_ minutes: Double, tag: SessionType?) -> StructuredWorkout {
        StructuredWorkout(
            name: "Run", sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(minutes * 60), target: .heartRateZone(2))])],
            sessionType: tag
        )
    }

    // MARK: The tag

    @Test("only a workout tagged long is a long run; untagged and other tags are not")
    func tagDecides() {
        #expect(run(60, tag: .long).isLongRun)
        #expect(!run(60, tag: nil).isLongRun)
        for type in SessionType.allCases where type != .long {
            #expect(!run(60, tag: type).isLongRun, "\(type)")
        }
    }

    @Test("a template passes its tag to the workouts it makes")
    func templateToWorkout() throws {
        let template = WorkoutTemplate(
            name: "Long run", sport: .running, parameters: [],
            blocks: [TemplateBlock(steps: [TemplateStep(kind: .work, goal: .time(.fixed(7200)), target: .heartRateZone(2))], repetitions: .fixed(1))],
            sessionType: .long
        )
        #expect(try template.instantiate().sessionType == .long)
        #expect(try template.instantiate().isLongRun)
    }

    @Test("a stored workout or template without the tag, or with an unknown one, reads as untagged")
    func codableTolerance() throws {
        let workout = run(60, tag: .long)
        let data = try JSONEncoder().encode(workout)
        #expect(try JSONDecoder().decode(StructuredWorkout.self, from: data).sessionType == .long)

        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["sessionType"] as? String == "long")
        object["sessionType"] = "ultraLong"
        let unknown = try JSONDecoder().decode(StructuredWorkout.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(unknown.sessionType == nil && !unknown.isLongRun)
        object["sessionType"] = nil
        let missing = try JSONDecoder().decode(StructuredWorkout.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(missing.sessionType == nil)

        let template = WorkoutTemplate(name: "T", sport: .running, parameters: [], blocks: [], sessionType: .long)
        var templateObject = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(template)) as? [String: Any])
        templateObject["sessionType"] = nil
        let legacy = try JSONDecoder().decode(WorkoutTemplate.self, from: JSONSerialization.data(withJSONObject: templateObject))
        #expect(legacy.sessionType == nil)
    }

    @Test("the calendar file keeps a template's tag and reads an unknown one as untagged")
    func calendarFile() throws {
        let template = WorkoutTemplate(
            name: "Long run", sport: .running, parameters: [],
            blocks: [TemplateBlock(steps: [TemplateStep(kind: .work, goal: .time(.fixed(7200)), target: .heartRateZone(2))], repetitions: .fixed(1))],
            sessionType: .long
        )
        let written = CalendarExport.Template(template)
        #expect(written.sessionType == "long")
        #expect(written.workoutTemplate()?.sessionType == .long)

        let data = try JSONEncoder().encode(written)
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["sessionType"] = "somethingNew"
        let unknown = try JSONDecoder().decode(CalendarExport.Template.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(unknown.workoutTemplate()?.sessionType == nil)
        object["sessionType"] = nil
        let old = try JSONDecoder().decode(CalendarExport.Template.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(old.workoutTemplate()?.sessionType == nil)
    }

    // MARK: The session

    @Test("the session's flag is the tag, whatever the day or the length")
    func sessionFlag() {
        let long = classifier.session(on: day(0), for: run(180, tag: .long), athlete: athlete)
        let shortLong = classifier.session(on: day(3), for: run(20, tag: .long), athlete: athlete)
        let longUntagged = classifier.session(on: day(6), for: run(240, tag: nil), athlete: athlete)
        #expect(long.isLongRun && shortLong.isLongRun)
        #expect(!longUntagged.isLongRun)
    }

    // MARK: With the day assigner

    /// The sessions of a micro when the generator picks, for each assigned run, a workout tagged with
    /// the run type's session type, so tags and assignments agree.
    private func sessions(_ result: DayAssignmentResult) -> [PlanSession] {
        result.assignments.map { assignment in
            let tag = assignment.runType.sessionType
            return classifier.session(on: assignment.day, for: run(assignment.runType == .long ? 150 : 45, tag: tag), athlete: athlete)
        }
    }

    private func availability(longSlot: Bool = true) -> RunAvailability {
        var availability = RunAvailability(
            slots: Dictionary(uniqueKeysWithValues: Weekday.allCases.map { ($0, [DaySlot.morning]) }),
            dayRunTypes: [.sunday: [.long]]
        )
        if !longSlot { availability[.sunday, .morning] = SlotOptions(longRunPossible: false) }
        return availability
    }

    @Test("for 7-, 10- and 14-day micros a session is a long run exactly where the assigner placed one")
    func agreesWithAssignments() {
        for days in [7, 10, 14] {
            let result = DayAssigner(paradigm: .polarized8020).assign(
                micro: day(0)...day(days - 1), availability: availability(), hardCount: 0, longCount: 1, calendar: calendar
            )
            let planned = sessions(result)
            let longDays = Set(result.assignments.filter { $0.runType == .long }.map(\.day))
            #expect(longDays.count == 1, "\(days)-day micro")
            #expect(Set(planned.filter { $0.isLongRun }.map(\.day)) == longDays, "\(days)-day micro")
            #expect(planned.count == result.assignments.count)
        }
    }

    // MARK: When the tag and the athlete's days disagree

    @Test("a long-tagged workout on a day that is not a long-run day is still a long run and is spaced as one")
    func taggedOnEasyDay() {
        // Tuesday and Wednesday name no long run, yet the tagged workouts there are long runs.
        let sessions = [
            classifier.session(on: day(1), for: run(150, tag: .long), athlete: athlete),
            classifier.session(on: day(2), for: run(150, tag: .long), athlete: athlete),
        ]
        #expect(sessions.allSatisfy { $0.isLongRun })
        let findings = PlanEvaluator().evaluate([], races: [], sessions: sessions, paradigm: .polarized8020).findings
        #expect(findings.contains { $0.rule == .hardSessionSpacing })
    }

    @Test("an untagged workout on the athlete's long-run day is not a long run, so it is not spaced as one")
    func untaggedOnLongDay() {
        let result = DayAssigner(paradigm: .polarized8020).assign(
            micro: day(0)...day(6), availability: availability(), hardCount: 0, longCount: 1, calendar: calendar
        )
        let long = result.assignments.first { $0.runType == .long }
        #expect(long != nil)
        let planned = classifier.session(on: long!.day, for: run(150, tag: nil), athlete: athlete)
        #expect(!planned.isLongRun)
        let hard = PlanSession(day: day(1), seconds: 3600, intensity: .high, speed: .fast)
        #expect(PlanEvaluator().evaluate([], races: [], sessions: [planned, hard], paradigm: .polarized8020).findings.filter { $0.rule == .hardSessionSpacing }.isEmpty)
    }

    @Test("when the assigner drops the long run no long-tagged workout is placed, so the micro has no long run")
    func droppedLongRun() {
        // The athlete's only running day names the long run but has no slot for it.
        let availability = RunAvailability(
            slots: [.sunday: [.morning]], slotOptions: [.sunday: [.morning: SlotOptions(longRunPossible: false)]], dayRunTypes: [.sunday: [.long]]
        )
        for days in [7, 10, 14] {
            let result = DayAssigner(paradigm: .polarized8020).assign(
                micro: day(0)...day(days - 1), availability: availability, hardCount: 0, longCount: 1, calendar: calendar
            )
            #expect(result.dropped.map(\.reason) == [.noLongRunSlot], "\(days)-day micro")
            #expect(sessions(result).allSatisfy { !$0.isLongRun }, "\(days)-day micro")
        }
    }
}
