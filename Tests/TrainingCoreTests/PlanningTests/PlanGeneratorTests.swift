import Foundation
import Testing
@testable import TrainingCore

@Suite("PlanGenerator")
struct PlanGeneratorTests {
    private let athlete = AthleteProfile.fixture()
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// A Monday, midnight UTC.
    private var monday: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 26))! }

    private func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: monday)! }

    /// Tuesday, Thursday and Sunday, one run each.
    private var threeRuns: PlanPreferences {
        var availability = RunAvailability()
        for weekday in [Weekday.tuesday, .thursday, .sunday] { availability[weekday] = [.morning] }
        return PlanPreferences(runAvailability: availability)
    }

    private let triphasicMacro = MacroTemplate(name: "Triphasic", mesoBlocks: [
        .init(phase: .base, microCount: 3), .init(phase: .structural, microCount: 6),
        .init(phase: .specific, microCount: 6), .init(phase: .taper, microCount: 1),
    ])
    private let polarizedMacro = MacroTemplate(name: "80/20", mesoBlocks: [
        .init(phase: .base, microCount: 4), .init(phase: .build, microCount: 5),
        .init(phase: .peak, microCount: 3), .init(phase: .taper, microCount: 1),
    ])

    /// A race on the last day of `micros` micros of `length` days that start on Monday.
    private func race(micros: Int, length: Int = 7, distance: Double = Race.marathonDistanceMeters, priority: RacePriority = .primary, target: SpecificPhaseTarget? = nil) -> Race {
        Race(name: "Race", date: day(micros * length - 1), priority: priority, distanceMeters: distance, specificPhaseTarget: target)
    }

    private func request(
        race: Race, paradigm: TrainingParadigm = .triphasic, macro: MacroTemplate? = nil, meso: MesocycleTemplate = .threeToOne,
        preferences: PlanPreferences? = nil, templates: [WorkoutTemplate] = BuiltInWorkoutTemplates.all, others: [Race] = [],
        guardrails: PlanGuardrails = PlanGuardrails()
    ) -> PlanRequest {
        PlanRequest(
            targetRace: race, otherRaces: others, paradigm: paradigm, macro: macro ?? triphasicMacro, meso: meso,
            preferences: preferences ?? threeRuns, athlete: athlete, today: monday, start: monday, templates: templates,
            startingVolume: VolumeTarget(measure: .durationSeconds, amount: 10_800)!,
            peakVolume: VolumeTarget(measure: .durationSeconds, amount: 18_000)!,
            guardrails: guardrails
        )
    }

    private func microCycles(_ proposal: PlanProposal) -> [TrainingCycle] {
        proposal.candidate.cycles.filter { $0.level == .micro }
    }

    @Test("a 16-week triphasic marathon plan lays out four meso blocks of seven-day micros ending on race day")
    func triphasicMarathonStructure() async throws {
        let race = race(micros: 16)
        let proposal = try await PlanGenerator.generate(request(race: race))
        let cycles = proposal.candidate.cycles

        #expect(cycles.filter { $0.level == .macro }.count == 1)
        #expect(cycles.filter { $0.level == .meso }.map(\.phase) == [.base, .structural, .specific, .taper])
        let micros = microCycles(proposal)
        #expect(micros.count == 16)
        #expect(micros.first?.dateRange.lowerBound == day(0))
        #expect(micros.last?.dateRange.upperBound == race.date)
        #expect(micros.map(\.loadRole) == [
            .build, .build, .build,
            .build, .build, .build, .recovery, .build, .build,
            .build, .build, .build, .recovery, .build, .build,
            .taper,
        ])
        #expect(proposal.targetRaceID == race.id)
        #expect(proposal.calibrationWarning == nil)
        #expect(proposal.candidate.compromises.filter { if case .leadTime = $0 { true } else { false } }.isEmpty)
    }

    @Test("every planned workout is in the library of templates, has a cycle, and its zone steps carry a pace")
    func plannedWorkoutsResolve() async throws {
        let proposal = try await PlanGenerator.generate(request(race: race(micros: 16, target: .pace(secondsPerKilometer: 270))))
        let candidate = proposal.candidate
        let workouts = Dictionary(uniqueKeysWithValues: candidate.workouts.map { ($0.id, $0) })
        let templateIDs = Set(BuiltInWorkoutTemplates.all.map(\.id))
        let cycleIDs = Set(candidate.cycles.map(\.id))

        // Three runs a micro, less the runs the adjust loop dropped and the ones with no place or template.
        let lostRuns = candidate.compromises.filter {
            switch $0 {
            case .unplacedSession, .missingTemplate: true
            default: false
            }
        }
        #expect(candidate.plannedActivities.count == 16 * 3 - proposal.levers.droppedDays.count - lostRuns.count)
        for planned in candidate.plannedActivities {
            let workout = try #require(workouts[planned.workoutID])
            #expect(templateIDs.contains(try #require(workout.templateID)))
            #expect(cycleIDs.contains(try #require(planned.cycleID)))
            // A zone step keeps its zone (the bpm comes when the workout is sent) and has the pace of that zone.
            for step in workout.blocks.flatMap(\.steps) {
                if case .heartRateZone = step.target, step.companionTarget == nil { Issue.record("zone step without a pace in \(workout.name)") }
                if case .heartRateRange = step.target { Issue.record("bpm stored in the plan in \(workout.name)") }
            }
        }
        #expect(candidate.sessions.count == candidate.plannedActivities.count)
        #expect(candidate.metrics.last?.day == day(16 * 7 - 1))
    }

    @Test("a plan that is not acceptable lists its risks as findings, an acceptable one has none")
    func evaluationListsRisks() async throws {
        let proposal = try await PlanGenerator.generate(request(race: race(micros: 16)))
        #expect(proposal.isAcceptable == proposal.risks.isEmpty)
        #expect(proposal.isAcceptable == (proposal.outcome == .acceptable))

        let strict = try await PlanGenerator.generate(request(race: race(micros: 16), guardrails: PlanGuardrails(maxMonotony: 0.01)))
        #expect(!strict.risks.isEmpty)
        #expect(!strict.isAcceptable)
        #expect(strict.outcome != .acceptable)
        #expect(!strict.history.isEmpty)
        #expect(strict.risks.allSatisfy { $0.severity == .risk })
    }

    @Test("a 10K plan with the polarized paradigm is laid out on its own phases and shows no calibration warning")
    func polarizedTenK() async throws {
        let race = race(micros: 13, distance: 10_000)
        let proposal = try await PlanGenerator.generate(request(race: race, paradigm: .polarized8020, macro: polarizedMacro))

        #expect(proposal.candidate.cycles.filter { $0.level == .meso }.map(\.phase) == [.base, .build, .peak, .taper])
        #expect(microCycles(proposal).count == 13)
        #expect(proposal.calibrationWarning == nil)
        #expect(!proposal.candidate.plannedActivities.isEmpty)
    }

    @Test("triphasic for a 10K shows the calibration warning with both distances")
    func calibrationWarning() async throws {
        var marathonOnly = TrainingParadigm.triphasic
        marathonOnly.distanceProfiles = [:]
        let proposal = try await PlanGenerator.generate(request(race: race(micros: 16, distance: 10_000), paradigm: marathonOnly))

        #expect(proposal.calibrationWarning == CalibrationWarning(raceDistanceMeters: 10_000, calibratedDistanceMeters: Race.marathonDistanceMeters))
    }

    @Test("a short lead time drops the structural phase and shortens the specific one, and reports both")
    func shortLeadTime() async throws {
        let proposal = try await PlanGenerator.generate(request(race: race(micros: 8)))

        #expect(proposal.candidate.cycles.filter { $0.level == .meso }.map(\.phase) == [.base, .specific, .taper])
        #expect(proposal.compromises.contains(.leadTime(LeadTimeCompromise(action: .phaseDropped(.structural), reason: .leadTimeTooShort(availableMicros: 8, neededMicros: 16)))))
        let shortened = proposal.compromises.compactMap { compromise -> LeadTimeCompromise.Action? in
            if case .leadTime(let change) = compromise, case .phaseShortened = change.action { change.action } else { nil }
        }
        #expect(shortened == [.phaseShortened(.specific, fromMicros: 6, toMicros: 4)])
    }

    @Test("a lead time below the taper and the shortest specific phase is an error, so is a race before the start")
    func errors() async throws {
        await #expect(throws: PlanGeneratorError.leadTime(.leadTimeTooShort(availableMicros: 1, requiredMicros: 2))) {
            try await PlanGenerator.generate(request(race: race(micros: 1)))
        }
        let earlier = Race(name: "Past", date: day(-3), priority: .primary, distanceMeters: Race.marathonDistanceMeters)
        await #expect(throws: PlanGeneratorError.noLayout) { try await PlanGenerator.generate(request(race: earlier)) }
    }

    @Test("no template is a compromise per run, the proposal is still returned")
    func missingTemplates() async throws {
        let proposal = try await PlanGenerator.generate(request(race: race(micros: 16), templates: []))

        #expect(proposal.candidate.plannedActivities.isEmpty)
        let missing = proposal.compromises.filter { if case .missingTemplate = $0 { true } else { false } }
        // Three runs a micro, minus the one on race day, which is the race.
        #expect(missing.count == 16 * 3 - 1)
    }

    @Test("a session the athlete's days cannot hold is reported with its reason")
    func unplacedSession() async throws {
        var availability = RunAvailability()
        availability[.sunday] = [.morning]
        let asked = request(race: race(micros: 16), preferences: PlanPreferences(runAvailability: availability))
        let proposal = try await PlanGenerator.generate(asked)

        let dropped = proposal.compromises.compactMap { compromise -> DroppedSession? in
            if case .unplacedSession(_, let session) = compromise { session } else { nil }
        }
        // The hard sessions of every micro (2 in a 7-day micro); the last micro's only free day is race day, so its long run is dropped too.
        #expect(asked.hardSessionsPerMicro == 2)
        #expect(dropped.count == 16 * asked.hardSessionsPerMicro + 1)
        #expect(dropped.filter { $0.kind == .hard }.count == 16 * asked.hardSessionsPerMicro)
        #expect(dropped.filter { $0.kind == .long }.map(\.reason) == [.noFreeDay])
    }

    @Test("micros of 7, 10 and 14 days are laid out whole and every run lands inside its micro", arguments: [7, 10, 14])
    func microLengths(length: Int) async throws {
        let meso = MesocycleTemplate(name: "3:1", microRoles: [.build, .build, .build, .recovery], microLengthDays: length)
        let macro = MacroTemplate(name: "Short", mesoBlocks: [.init(phase: .base, microCount: 3), .init(phase: .specific, microCount: 3), .init(phase: .taper, microCount: 1)])
        var preferences = threeRuns
        preferences.runAvailability[.saturday] = [.morning]
        let proposal = try await PlanGenerator.generate(request(race: race(micros: 7, length: length), macro: macro, meso: meso, preferences: preferences))

        let micros = microCycles(proposal)
        #expect(micros.count == 7)
        #expect(micros.allSatisfy { calendar.dateComponents([.day], from: $0.dateRange.lowerBound, to: $0.dateRange.upperBound).day == length - 1 })
        for planned in proposal.candidate.plannedActivities {
            let micro = try #require(micros.first { $0.id == planned.cycleID })
            #expect(micro.dateRange.contains(planned.date))
        }
    }

    @Test("two runs on a day give two planned workouts that day")
    func twoRunsADay() async throws {
        var availability = RunAvailability()
        availability[.tuesday] = [.morning, .evening]
        availability.setRuns(2, on: .tuesday)
        availability[.thursday] = [.morning]
        availability[.sunday] = [.morning]
        let proposal = try await PlanGenerator.generate(request(race: race(micros: 16), preferences: PlanPreferences(runAvailability: availability)))

        let perDay = Dictionary(grouping: proposal.candidate.plannedActivities, by: \.date).mapValues(\.count)
        #expect(perDay[day(1)] == 2)
        #expect(perDay[day(3)] == 1)
        #expect(proposal.candidate.sessions.filter { $0.day == day(1) }.count == 2)
    }

    @Test("a secondary race gets a taper micro and a recovery micro")
    func secondaryRace() async throws {
        let secondary = Race(name: "10K", date: day(5 * 7 + 3), priority: .secondary, distanceMeters: 10_000)
        let proposal = try await PlanGenerator.generate(request(race: race(micros: 16), others: [secondary]))

        let roles = microCycles(proposal).map(\.loadRole)
        #expect(roles[5] == .taper)
        #expect(roles[6] == .recovery)
    }

    @Test("two identical requests give the same plan apart from ids")
    func determinism() async throws {
        let first = try await PlanGenerator.generate(request(race: race(micros: 16)))
        let second = try await PlanGenerator.generate(request(race: race(micros: 16)))

        func shape(_ proposal: PlanProposal) -> [String] {
            let workouts = Dictionary(uniqueKeysWithValues: proposal.candidate.workouts.map { ($0.id, $0) })
            return proposal.candidate.plannedActivities.map { planned in
                let workout = workouts[planned.workoutID]
                return "\(planned.date.timeIntervalSince1970) \(workout?.templateID?.uuidString ?? "-") \(workout?.parameterValues?.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" } ?? [])"
            }
        }
        #expect(shape(first) == shape(second))
        #expect(first.candidate.cycles.map { [$0.name, "\($0.level)", $0.phase.id, "\($0.loadRole as Any)", "\($0.dateRange)"] }
            == second.candidate.cycles.map { [$0.name, "\($0.level)", $0.phase.id, "\($0.loadRole as Any)", "\($0.dateRange)"] })
        #expect(first.candidate.metrics.map(\.ctl) == second.candidate.metrics.map(\.ctl))
        #expect(first.candidate.metrics.map(\.tsb) == second.candidate.metrics.map(\.tsb))
        #expect(first.candidate.sessions == second.candidate.sessions)
        #expect(first.compromises == second.compromises)
        #expect(first.history == second.history)
        #expect(first.levers == second.levers)
    }

    @Test("levers drop a day's runs, turn a micro into a recovery micro and scale its volume")
    func levers() async throws {
        let generator = PlanGenerator(request: request(race: race(micros: 16)))
        let plain = try await generator.candidate(levers: .none, today: monday)

        let dropped = try await generator.candidate(levers: PlanLevers(droppedDays: [day(1)]), today: monday)
        #expect(plain.plannedActivities.contains { $0.date == day(1) })
        #expect(!dropped.plannedActivities.contains { $0.date == day(1) })

        let down = try await generator.candidate(levers: PlanLevers(downWeeks: [day(14)]), today: monday)
        #expect(down.cycles.filter { $0.level == .micro }[2].loadRole == .recovery)

        let seconds: (PlanCandidate) -> TimeInterval = { candidate in
            candidate.sessions.filter { $0.day >= self.day(7) && $0.day < self.day(14) }.reduce(0) { $0 + $1.seconds }
        }
        let scaled = try await generator.candidate(levers: PlanLevers(volumeScales: [day(7): 0.5]), today: monday)
        #expect(seconds(scaled) < seconds(plain))
    }

    @Test("easing a day turns a hard run into an easy one")
    func easedDay() async throws {
        let generator = PlanGenerator(request: request(race: race(micros: 16)))
        let plain = try await generator.candidate(levers: .none, today: monday)
        let hardDay = try #require(plain.sessions.first { $0.intensity >= .high }?.day)

        let eased = try await generator.candidate(levers: PlanLevers(easedDays: [hardDay]), today: monday)
        #expect(!eased.sessions.contains { $0.day == hardDay && $0.intensity >= .high })
        #expect(eased.sessions.contains { $0.day == hardDay })
    }

    @Test("volume in TRIMP, or a limit in another measure, is an error")
    func volumeErrors() async throws {
        var trimp = request(race: race(micros: 16))
        trimp.startingVolume = VolumeTarget(measure: .trimp, amount: 300)!
        trimp.peakVolume = VolumeTarget(measure: .trimp, amount: 500)!
        await #expect(throws: PlanGeneratorError.unsupportedVolumeMeasure(.trimp)) { try await PlanGenerator.generate(trimp) }

        var mismatched = request(race: race(micros: 16))
        mismatched.preferences.maxWeeklyVolume[.running] = VolumeTarget(measure: .distanceMeters, amount: 40_000)!
        await #expect(throws: PlanGeneratorError.volumeCurve(.mismatchedMeasure)) { try await PlanGenerator.generate(mismatched) }
    }

    @Test("the weekly maximum caps the peak, and a micro that still needs more is reported")
    func weeklyMaximum() async throws {
        var capped = request(race: race(micros: 16))
        capped.preferences.maxWeeklyVolume[.running] = VolumeTarget(measure: .durationSeconds, amount: 3_600)!
        let proposal = try await PlanGenerator.generate(capped)

        #expect(proposal.compromises.contains(.overriddenPreference(.maxWeeklyVolume)))
        var roomy = request(race: race(micros: 16))
        roomy.preferences.maxWeeklyVolume[.running] = VolumeTarget(measure: .durationSeconds, amount: 100_000)!
        #expect(!(try await PlanGenerator.generate(roomy)).compromises.contains(.overriddenPreference(.maxWeeklyVolume)))
    }

    @Test("dropping the conditioning phase against the athlete's wish is an overridden preference")
    func conditioningOverridden() async throws {
        let macro = MacroTemplate(name: "Triphasic", mesoBlocks: [.init(phase: .conditioning, microCount: 4)] + triphasicMacro.mesoBlocks)
        var wanted = threeRuns
        wanted.includeConditioning = true
        let proposal = try await PlanGenerator.generate(request(race: race(micros: 16), macro: macro, preferences: wanted))

        #expect(proposal.compromises.contains(.overriddenPreference(.includeConditioning)))
    }

    @Test("history seeds the series, so the TSB rules run on the plan's first weeks")
    func withHistory() async throws {
        var history: [Activity] = []
        for offset in stride(from: -84, to: 0, by: 2) {
            history.append(Activity(source: .manual, sport: .running, start: day(offset), duration: 3600, perceivedExertion: 5))
        }
        var withHistory = request(race: race(micros: 16))
        withHistory.activities = history
        let proposal = try await PlanGenerator.generate(withHistory)

        #expect(proposal.candidate.metrics.first?.day == day(-84))
        #expect(proposal.candidate.metrics.first { $0.day >= day(0) }?.isWarmingUp == false)
        #expect(proposal.candidate.metrics.contains { !$0.isProjected })
    }

    @Test("recent sessions reach the evaluator, so a long jump in the first week is a risk")
    func recentSessions() async throws {
        var asked = request(race: race(micros: 16))
        asked.recentSessions = [PlanSession(day: day(-3), seconds: 600, intensity: .low, speed: .slow, isLongRun: true)]
        let candidate = try await PlanGenerator(request: asked).candidate(levers: .none, today: monday)

        #expect(candidate.sessions.first?.day == day(-3))
        let findings = PlanEvaluator().evaluate(candidate.metrics, races: [], sessions: candidate.sessions)
        #expect(findings.findings.contains { $0.rule == .longestRun })
    }

    @Test("a time zone with daylight saving keeps the layout, the runs and the series on whole days")
    func daylightSaving() async throws {
        let zone = TimeZone(identifier: "Europe/Amsterdam")!
        var local = Calendar(identifier: .gregorian)
        local.timeZone = zone
        let start = local.date(from: DateComponents(year: 2026, month: 10, day: 12))!
        let raceDay = local.date(from: DateComponents(year: 2026, month: 10, day: 12 + 8 * 7 - 1, hour: 10))!
        var asked = request(race: Race(name: "R", date: raceDay, priority: .primary, distanceMeters: Race.marathonDistanceMeters), macro: MacroTemplate(name: "Short", mesoBlocks: [.init(phase: .base, microCount: 4), .init(phase: .specific, microCount: 3), .init(phase: .taper, microCount: 1)]))
        asked.athlete = AthleteProfile.fixture(timeZoneIdentifier: zone.identifier)
        asked.start = start
        asked.today = start
        let proposal = try await PlanGenerator.generate(asked)

        let micros = proposal.candidate.cycles.filter { $0.level == .micro }
        #expect(micros.count == 8)
        #expect(micros.allSatisfy { $0.dateRange.lowerBound == local.startOfDay(for: $0.dateRange.lowerBound) })
        #expect(proposal.candidate.plannedActivities.allSatisfy { $0.date == local.startOfDay(for: $0.date) })
        #expect(proposal.candidate.metrics.last?.day == local.startOfDay(for: raceDay))
        // The race has a time of day; its race-day TSB is still looked up on the day's start.
        #expect(proposal.candidate.metrics.contains { $0.day == local.startOfDay(for: raceDay) })
    }

    @Test("a cancelled generation throws and returns nothing")
    func cancellation() async {
        let request = request(race: race(micros: 16))
        let task = Task { () async throws -> PlanProposal in
            await Task.yield()
            withUnsafeCurrentTask { $0?.cancel() }
            return try await PlanGenerator.generate(request)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}

@MainActor
@Suite("PlanGenerator commit", .serialized)
struct PlanGeneratorCommitTests {
    private func makeModel() -> TrainingModel {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store, trainingPlanStore: store
        )
        return TrainingModel(stores: stores, athlete: AthleteProfile.fixture())
    }

    @Test("a generated proposal commits as a draft, or as the active plan, with its workouts in the library")
    func commits() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let monday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 26))!
        var availability = RunAvailability()
        for weekday in [Weekday.tuesday, .thursday, .sunday] { availability[weekday] = [.morning] }
        let race = Race(name: "Marathon", date: calendar.date(byAdding: .day, value: 8 * 7 - 1, to: monday)!, priority: .primary, distanceMeters: Race.marathonDistanceMeters)
        let proposal = try await PlanGenerator.generate(PlanRequest(
            targetRace: race, paradigm: .polarized8020,
            macro: MacroTemplate(name: "80/20", mesoBlocks: [.init(phase: .base, microCount: 3), .init(phase: .build, microCount: 3), .init(phase: .peak, microCount: 1), .init(phase: .taper, microCount: 1)]),
            meso: .threeToOne, preferences: PlanPreferences(runAvailability: availability), athlete: AthleteProfile.fixture(),
            today: monday, start: monday, templates: BuiltInWorkoutTemplates.all,
            startingVolume: VolumeTarget(measure: .durationSeconds, amount: 10_800)!, peakVolume: VolumeTarget(measure: .durationSeconds, amount: 18_000)!
        ))
        let model = makeModel()

        let draft = try await model.commit(proposal, named: "Draft", asOf: monday)
        #expect(draft.status == .draft)
        let active = try await model.commit(proposal, named: "Active", activate: true, acceptingRisks: true, asOf: monday)
        #expect(active.status == .active)
        let stored = try await model.plannedActivities(ofPlan: active.id, in: monday...race.date)
        #expect(stored.count == proposal.candidate.plannedActivities.count)
        #expect(Set(stored.map(\.workoutID)) == Set(proposal.candidate.plannedActivities.map(\.workoutID)))
    }
}
