import Foundation
import Testing
@testable import TrainingCore

/// Recovery days around a workout, per template (MVP5-147).
@Suite("RecoveryDays")
struct RecoveryDaysTests {
    private func template(_ type: SessionType?, recovery: RecoveryDays? = nil) -> WorkoutTemplate {
        WorkoutTemplate(
            name: "T", sport: .running, parameters: [],
            blocks: [TemplateBlock(steps: [TemplateStep(kind: .work, goal: .time(.fixed(600)), target: .heartRateZone(2))])],
            sessionType: type, recoveryDays: recovery
        )
    }

    @Test("days below zero are raised to zero, and 0 and 0 want nothing")
    func clamping() {
        let days = RecoveryDays(before: -2, after: 3)
        #expect(days.before == 0 && days.after == 3 && !days.isNone)
        #expect(RecoveryDays(before: 0, after: -1).isNone)
    }

    @Test("by default intense sessions want 0 days before and the paradigm's spacing after; easy and recovery runs want nothing")
    func defaults() {
        for type in [SessionType.interval, .tempo, .hillRepeats] {
            #expect(template(type).effectiveRecoveryDays(defaultAfter: 2, longRunsNeedRecovery: false) == RecoveryDays(before: 0, after: 2))
        }
        for type in [SessionType.easy, .recovery, nil] {
            #expect(template(type).effectiveRecoveryDays(defaultAfter: 2, longRunsNeedRecovery: true) == nil)
        }
        // A long run counts as intense only where the paradigm spaces long runs like hard ones (not for an ultra).
        #expect(template(.long).effectiveRecoveryDays(defaultAfter: 2, longRunsNeedRecovery: true) == RecoveryDays(before: 0, after: 2))
        #expect(template(.long).effectiveRecoveryDays(defaultAfter: 2, longRunsNeedRecovery: false) == nil)
        // A paradigm with no spacing asks for nothing by default.
        #expect(template(.interval).effectiveRecoveryDays(defaultAfter: nil, longRunsNeedRecovery: true) == nil)
        #expect(template(.interval).effectiveRecoveryDays(defaultAfter: 0, longRunsNeedRecovery: true) == nil)
    }

    @Test("a template's own days win over the default of its session type, in either direction")
    func explicitWins() {
        #expect(template(.long, recovery: RecoveryDays(before: 1, after: 3)).effectiveRecoveryDays(defaultAfter: 2, longRunsNeedRecovery: false)
            == RecoveryDays(before: 1, after: 3))
        #expect(template(.easy, recovery: RecoveryDays(before: 0, after: 1)).effectiveRecoveryDays(defaultAfter: 2, longRunsNeedRecovery: false)
            == RecoveryDays(before: 0, after: 1))
        #expect(template(.interval, recovery: RecoveryDays(before: 0, after: 0)).effectiveRecoveryDays(defaultAfter: 2, longRunsNeedRecovery: true) == nil)
    }

    @Test("only the alternation run has its own days among the built-in templates: 1 before and 3 after")
    func builtIns() {
        #expect(BuiltInWorkoutTemplates.alternationRun.recoveryDays == RecoveryDays(before: 1, after: 3))
        #expect(BuiltInWorkoutTemplates.all.filter { $0.recoveryDays != nil }.map(\.name) == ["Alternation Run"])
    }

    @Test("a template round-trips with its days; one stored without them, or with something unreadable, reads as the default")
    func coding() throws {
        let with = template(.long, recovery: RecoveryDays(before: 1, after: 3))
        #expect(try JSONDecoder().decode(WorkoutTemplate.self, from: JSONEncoder().encode(with)) == with)

        let plain = template(.interval)
        let data = try JSONEncoder().encode(plain)
        #expect(!String(decoding: data, as: UTF8.self).contains("recoveryDays"))
        #expect(try JSONDecoder().decode(WorkoutTemplate.self, from: data).recoveryDays == nil)

        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["recoveryDays"] = "lots"
        #expect(try JSONDecoder().decode(WorkoutTemplate.self, from: JSONSerialization.data(withJSONObject: object)).recoveryDays == nil)
        object["recoveryDays"] = ["before": -3, "after": 2]
        #expect(try JSONDecoder().decode(WorkoutTemplate.self, from: JSONSerialization.data(withJSONObject: object)).recoveryDays == RecoveryDays(before: 0, after: 2))
    }
}

/// The day assigner and the generator with recovery days (MVP5-147).
@Suite("Recovery days in the plan")
struct RecoveryDaysPlanTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private var monday: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 26))! }
    private func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: monday)! }

    @Test("a hard session is not placed sooner after an earlier workout than that workout wants")
    func assignerWantedDays() {
        var availability = RunAvailability()
        for weekday in Weekday.allCases { availability[weekday] = [.morning] }
        let micro = day(0)...day(6)
        let free = DayAssigner().assign(micro: micro, availability: availability, hardCount: 1, longCount: 0, calendar: calendar)
        #expect(free.assignments.first { $0.runType == .interval || $0.runType == .threshold }?.day == day(0))

        // A workout the day before the micro wants 3 days after it: the first hard day is day 2.
        let wanted = DayAssigner().assign(
            micro: micro, availability: availability, hardCount: 1, longCount: 0,
            recoveryAfter: [day(-1): 3], calendar: calendar
        )
        #expect(wanted.assignments.first { $0.runType == .interval || $0.runType == .threshold }?.day == day(2))
    }

    private let athlete = AthleteProfile.fixture()
    private let macro = MacroTemplate(name: "Triphasic", mesoBlocks: [
        .init(phase: .base, microCount: 2), .init(phase: .structural, microCount: 2),
        .init(phase: .specific, microCount: 4), .init(phase: .taper, microCount: 1),
    ])

    /// A 9-week triphasic plan with the given hard and long weekdays (one run each, morning), the easy
    /// runs on the other days, and only the given templates.
    private func request(
        hard: [Weekday], long: [Weekday], templates: [WorkoutTemplate], hardSessions: Int = 1,
        distance: Double = Race.marathonDistanceMeters, longRuns: Int = 1
    ) -> PlanRequest {
        var availability = RunAvailability()
        for weekday in Weekday.allCases { availability[weekday] = [.morning] }
        for weekday in hard { availability.setRunTypes([.interval, .threshold, .easy], on: weekday) }
        for weekday in long { availability.setRunTypes([.long, .easy], on: weekday) }
        let race = Race(name: "A race", date: day(9 * 7 - 1), priority: .primary, distanceMeters: distance)
        return PlanRequest(
            targetRace: race, paradigm: .triphasic, macro: macro, meso: .threeToOne,
            preferences: PlanPreferences(runAvailability: availability), athlete: athlete, today: monday, start: monday,
            templates: templates,
            startingVolume: VolumeTarget(measure: .durationSeconds, amount: 14_400)!,
            peakVolume: VolumeTarget(measure: .durationSeconds, amount: 21_600)!,
            hardSessionsPerMicro: hardSessions,
            longRunsPerMicro: longRuns
        )
    }

    private let basics = [BuiltInWorkoutTemplates.easyRun, BuiltInWorkoutTemplates.recoveryRun, BuiltInWorkoutTemplates.shortIntervalRun]
    private func names(_ candidate: PlanCandidate) -> [String] {
        let workouts = Dictionary(uniqueKeysWithValues: candidate.workouts.map { ($0.id, $0) })
        return candidate.plannedActivities.compactMap { workouts[$0.workoutID]?.templateID }.compactMap { id in
            BuiltInWorkoutTemplates.all.first { $0.id == id }?.name
        }
    }

    /// The demanding workouts of the plan in date order, with the days they want free.
    private func demands(of candidate: PlanCandidate, templates: [WorkoutTemplate]) -> [(date: Date, days: RecoveryDays)] {
        let workouts = Dictionary(uniqueKeysWithValues: candidate.workouts.map { ($0.id, $0) })
        return candidate.plannedActivities.sorted { $0.date < $1.date }.compactMap { planned in
            guard let id = workouts[planned.workoutID]?.templateID,
                  let days = templates.first(where: { $0.id == id })?.effectiveRecoveryDays(defaultAfter: 2, longRunsNeedRecovery: true)
            else { return nil }
            return (planned.date, days)
        }
    }

    private func shortfalls(_ proposal: PlanProposal) -> [(template: String, needed: Int, available: Int)] {
        proposal.compromises.compactMap { compromise in
            if case .recoveryDaysShort(_, let template, let needed, let available) = compromise { (template, needed, available) } else { nil }
        }
    }

    @Test("an alternation run is planned where its neighbours leave it 1 day before and 3 after")
    func alternationFits() async throws {
        // Hard on Wednesday, long on Sunday: Wednesday to Sunday is 4 days, Sunday to Wednesday 3.
        let asked = request(hard: [.wednesday], long: [.sunday], templates: basics + [BuiltInWorkoutTemplates.alternationRun])
        let proposal = try await PlanGenerator.generate(asked)

        #expect(names(proposal.candidate).contains("Alternation Run"))
        #expect(!proposal.compromises.contains { if case .recoveryDaysShort = $0 { true } else { false } })
        // Every pair of demanding workouts is at least the earlier one's days after plus the later one's days before apart.
        let all = demands(of: proposal.candidate, templates: asked.templates)
        for (offset, earlier) in all.enumerated() {
            for later in all[(offset + 1)...] {
                let gap = calendar.dateComponents([.day], from: earlier.date, to: later.date).day ?? 0
                #expect(gap >= earlier.days.after + later.days.before, "\(gap) days from \(earlier.date) to \(later.date)")
            }
        }
    }

    @Test("an alternation run that would sit too close to the next hard session is left out for another long run")
    func alternationRefit() async throws {
        // Monday to Wednesday is 2 days, less than the 3 an alternation run wants after it.
        let asked = request(
            hard: [.wednesday], long: [.monday],
            templates: basics + [BuiltInWorkoutTemplates.alternationRun, BuiltInWorkoutTemplates.longRun]
        )
        let proposal = try await PlanGenerator.generate(asked)

        #expect(!names(proposal.candidate).contains("Alternation Run"))
        #expect(names(proposal.candidate).contains("Long run"))
        #expect(!proposal.compromises.contains { if case .recoveryDaysShort = $0 { true } else { false } })
    }

    @Test("with no other long run the alternation run keeps its day and the shortfall is reported")
    func alternationCompromise() async throws {
        let asked = request(hard: [.wednesday], long: [.monday], templates: basics + [BuiltInWorkoutTemplates.alternationRun])
        let proposal = try await PlanGenerator.generate(asked)

        #expect(names(proposal.candidate).contains("Alternation Run"))
        let shortfalls = proposal.compromises.compactMap { compromise -> (String, Int, Int)? in
            if case .recoveryDaysShort(_, let template, let needed, let available) = compromise { (template, needed, available) } else { nil }
        }
        #expect(!shortfalls.isEmpty)
        // One report per pair of workouts, on the alternation run that wants the days: not again on the
        // hard session after it.
        #expect(shortfalls.allSatisfy { $0.0 == "Alternation Run" && $0.1 == 3 && $0.2 == 2 })
    }

    @Test("when no day gives the days an earlier workout wants, the paradigm's spacing decides and the shortfall is reported")
    func softAcrossMicros() async throws {
        // Long on Sunday, the only hard day Tuesday: 2 days after the alternation run, which wants 3.
        let asked = request(hard: [.tuesday], long: [.sunday], templates: basics + [BuiltInWorkoutTemplates.alternationRun])
        let proposal = try await PlanGenerator.generate(asked)

        // The hard session keeps its Tuesday (it is not dropped), and the plan says it is short.
        #expect(!proposal.compromises.contains { if case .unplacedSession(_, let dropped) = $0 { dropped.kind == .hard } else { false } })
        #expect(proposal.compromises.contains { if case .recoveryDaysShort(_, _, 3, 2) = $0 { true } else { false } })
    }

    @Test("a hard session after an alternation run in the micro before is placed 3 days after it")
    func carriedIntoNextMicro() async throws {
        // Long on Sunday (the last day of a micro), hard on Tuesday and Wednesday: Tuesday is 2 days after
        // the alternation run, Wednesday 3, so the hard session of the next micro takes Wednesday.
        let asked = request(hard: [.tuesday, .wednesday], long: [.sunday], templates: basics + [BuiltInWorkoutTemplates.alternationRun])
        let candidate = try await PlanGenerator.generate(asked).candidate
        let workouts = Dictionary(uniqueKeysWithValues: candidate.workouts.map { ($0.id, $0) })
        let alternationDays = candidate.plannedActivities
            .filter { workouts[$0.workoutID]?.templateID == BuiltInWorkoutTemplates.alternationRun.id }.map(\.date)
        let hardDays = candidate.plannedActivities
            .filter { workouts[$0.workoutID]?.sessionType == .interval }.map(\.date)
        #expect(!alternationDays.isEmpty)
        for alternation in alternationDays {
            for hard in hardDays where hard > alternation {
                let gap = calendar.dateComponents([.day], from: alternation, to: hard).day ?? 0
                #expect(gap >= 3 || gap == 0, "hard session \(gap) days after the alternation run on \(alternation)")
            }
        }
    }

    @Test("an alternation run right after a hard session of the micro before is short of the day it wants before it")
    func carriedBefore() async throws {
        // Hard on Sunday (the last day of a micro), long on Tuesday: 2 days, and the hard session wants 2 after and the
        // alternation run 1 before. The hard session of the micro before is carried in and compared in full.
        let asked = request(hard: [.sunday], long: [.tuesday], templates: basics + [BuiltInWorkoutTemplates.alternationRun])
        let proposal = try await PlanGenerator.generate(asked)

        let reported = shortfalls(proposal)
        #expect(!reported.isEmpty)
        #expect(reported.allSatisfy { $0.template == "Alternation Run" && $0.needed == 3 && $0.available == 2 })
    }

    @Test("a template of any kind can ask for its own days: a long run that wants 5 after it is short where the next hard session is 2 away")
    func customTemplate() async throws {
        let longRun = BuiltInWorkoutTemplates.longRun
        let heavy = WorkoutTemplate(
            name: "Heavy long", sport: longRun.sport, parameters: longRun.parameters, blocks: longRun.blocks,
            sessionType: .long, recoveryDays: RecoveryDays(before: 0, after: 5)
        )
        let proposal = try await PlanGenerator.generate(request(hard: [.wednesday], long: [.monday], templates: basics + [heavy]))

        let reported = shortfalls(proposal)
        #expect(!reported.isEmpty)
        #expect(reported.allSatisfy { $0.template == "Heavy long" && $0.needed == 5 && $0.available == 2 })
    }

    @Test("an ultra does not ask its long runs for recovery days: they may sit next to a hard session and to each other")
    func ultraLongRuns() async throws {
        let templates = basics + [BuiltInWorkoutTemplates.longRun]
        let marathon = try await PlanGenerator.generate(request(hard: [.tuesday], long: [.saturday, .sunday], templates: templates, longRuns: 2))
        let ultra = try await PlanGenerator.generate(request(hard: [.tuesday], long: [.saturday, .sunday], templates: templates, distance: 100_000, longRuns: 2))

        func longRuns(_ proposal: PlanProposal) -> Int {
            proposal.candidate.workouts.filter { $0.sessionType == .long }.count
        }
        #expect(shortfalls(ultra).isEmpty)
        // A marathon spaces its long runs like hard sessions, so Saturday and Sunday cannot both be used.
        #expect(longRuns(ultra) > longRuns(marathon))
    }

    @Test("a plan without alternation runs is unchanged: the default days are the paradigm's spacing")
    func defaultsUnchanged() async throws {
        let asked = request(hard: [.tuesday, .thursday], long: [.saturday, .sunday], templates: basics + [BuiltInWorkoutTemplates.longRun], hardSessions: 2)
        let proposal = try await PlanGenerator.generate(asked)
        #expect(!proposal.compromises.contains { if case .recoveryDaysShort = $0 { true } else { false } })
    }
}
