import Foundation
import Testing
@testable import TrainingCore

@Suite("WorkoutRanker")
struct WorkoutRankerTests {
    private let athlete = AthleteProfile.fixture()
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private var monday: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 26))! }
    private func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: monday)! }

    private actor FixtureCache {
        static let shared = FixtureCache()
        private var stored: Fixture?
        func fixture(_ make: () async throws -> Fixture) async throws -> Fixture {
            if let stored { return stored }
            let made = try await make()
            stored = made
            return made
        }
    }

    /// A few templates of each kind, so a ranking without a target stays small.
    private var someTemplates: [WorkoutTemplate] {
        ["Easy run", "Tempo run", "Base Full-out hill sprints", "Long run", "Short interval run"].compactMap { name in
            BuiltInWorkoutTemplates.all.first { $0.name == name }
        }
    }

    private struct Fixture: Sendable {
        let proposal: PlanProposal
        let activities: [Activity]
        let race: Race
    }

    /// A plan of 16 weeks for a marathon, four runs a week.
    private func fixture() async throws -> Fixture {
        try await FixtureCache.shared.fixture { try await makeFixture() }
    }

    private func makeFixture() async throws -> Fixture {
        var availability = RunAvailability()
        for weekday in [Weekday.tuesday, .thursday, .saturday, .sunday] { availability[weekday] = [.morning] }
        let race = Race(name: "A race", date: day(16 * 7 - 1), priority: .primary, distanceMeters: Race.marathonDistanceMeters)
        var request = PlanRequest(
            targetRace: race, paradigm: .triphasic,
            macro: MacroTemplate(name: "Triphasic", mesoBlocks: [
                .init(phase: .base, microCount: 3), .init(phase: .structural, microCount: 6),
                .init(phase: .specific, microCount: 6), .init(phase: .taper, microCount: 1),
            ]),
            meso: .threeToOne, preferences: PlanPreferences(runAvailability: availability), athlete: athlete,
            today: monday, start: monday, templates: BuiltInWorkoutTemplates.all,
            startingVolume: VolumeTarget(measure: .durationSeconds, amount: 10_800)!,
            peakVolume: VolumeTarget(measure: .durationSeconds, amount: 18_000)!
        )
        let history = stride(from: -84, to: 0, by: 2).map { Activity(source: .manual, sport: .running, start: day($0), duration: 3600, perceivedExertion: 1) }
        request.activities = history
        return Fixture(proposal: try await PlanGenerator.generate(request), activities: history, race: race)
    }

    private func rank(_ fixture: Fixture, replacing: PlannedActivity?, on date: Date, microSeconds: TimeInterval? = nil, templates: [WorkoutTemplate]? = nil) async throws -> [RankedWorkout] {
        let candidate = fixture.proposal.candidate
        return try await WorkoutRanker.rank(
            day: date, replacing: replacing, plan: candidate.plannedActivities, workouts: candidate.workouts, templates: templates ?? BuiltInWorkoutTemplates.all,
            cycles: candidate.cycles, activities: fixture.activities, races: [fixture.race], athlete: athlete, paradigm: .triphasic,
            targetRace: fixture.race, microSeconds: microSeconds, today: monday
        )
    }

    @Test("replacing a workout offers the same template with different values, on the grid, near the replaced load")
    func replacing() async throws {
        let fixture = try await fixture()
        let candidate = fixture.proposal.candidate
        let planned = try #require(candidate.plannedActivities.sorted { $0.date < $1.date }.dropFirst(8).first)
        let old = try #require(candidate.workouts.first { $0.id == planned.workoutID })
        let target = TRIMPPlanEstimator().estimatedLoad(for: old, athlete: athlete).value
        let ranked = try await rank(fixture, replacing: planned, on: planned.date)

        #expect(!ranked.isEmpty)
        let byTemplate = Dictionary(grouping: ranked, by: \.template.id)
        #expect(byTemplate.values.contains { $0.count > 1 }, "a template comes back with several values")
        for item in ranked {
            #expect(abs(item.load - target) / target <= WorkoutRanker.targetMargin + 1e-9)
            for parameter in item.template.parameters {
                guard let range = parameter.range, let value = item.values[parameter.key] else { continue }
                #expect(ParameterGrid.values(in: range, unit: parameter.unit).contains { abs($0 - value) < 1e-9 }, "\(parameter.key) = \(value)")
            }
        }
    }

    @Test("the list is ordered: workouts with problems come after those without")
    func ordered() async throws {
        let fixture = try await fixture()
        let candidate = fixture.proposal.candidate
        let planned = try #require(candidate.plannedActivities.sorted { $0.date < $1.date }.dropFirst(8).first)
        let ranked = try await rank(fixture, replacing: planned, on: planned.date)
        func problems(_ item: RankedWorkout) -> Int {
            item.reasons.filter { if case .addsRisk = $0 { true } else if case .recoveryDaysShort = $0 { true } else { false } }.count
        }
        let counts = ranked.map(problems)
        #expect(counts == counts.sorted())
    }

    @Test("a workout outside the phase stays in the list with its reason, below the ones inside it")
    func outsidePhase() async throws {
        let fixture = try await fixture()
        let candidate = fixture.proposal.candidate
        let taper = try #require(candidate.cycles.filter { $0.level == .micro && $0.phase == .taper }.first)
        let date = calendar.startOfDay(for: taper.dateRange.lowerBound)
        let ranked = try await rank(fixture, replacing: nil, on: date, templates: someTemplates)
        let outside = ranked.filter { $0.reasons.contains { if case .notAskedInPhase = $0 { true } else { false } } }
        let inside = ranked.filter { !outside.contains($0) }
        #expect(!outside.isEmpty && !inside.isEmpty)
        // At the same number of problems, the ones the phase asks for come first.
        func problems(_ item: RankedWorkout) -> Int {
            item.reasons.filter { if case .addsRisk = $0 { true } else if case .recoveryDaysShort = $0 { true } else { false } }.count
        }
        for (earlier, later) in zip(ranked, ranked.dropFirst()) where problems(earlier) == problems(later) {
            #expect(!(outside.contains(earlier) && inside.contains(later)))
        }
    }

    @Test("adding with a micro volume aims at the time the micro has left")
    func adding() async throws {
        let fixture = try await fixture()
        let candidate = fixture.proposal.candidate
        let micro = try #require(candidate.cycles.filter { $0.level == .micro }.sorted { $0.dateRange.lowerBound < $1.dateRange.lowerBound }.dropFirst(4).first)
        let free = try #require((0..<7).map { calendar.date(byAdding: .day, value: $0, to: micro.dateRange.lowerBound)! }.first { date in
            !candidate.plannedActivities.contains { calendar.isDate($0.date, inSameDayAs: date) }
        })
        let ranked = try await rank(fixture, replacing: nil, on: free, microSeconds: 6 * 3600)
        #expect(!ranked.isEmpty)
        #expect(ranked.allSatisfy { $0.microSeconds != nil })
    }

    // MARK: - Hand-made plans

    private func template(_ name: String) throws -> WorkoutTemplate {
        try #require(BuiltInWorkoutTemplates.all.first { $0.name == name })
    }

    /// A week of a specific-phase micro (days 7 to 13) with a long run on day 11, and nothing else planned.
    private func week(longRunDay: Int = 11) throws -> (plan: [PlannedActivity], workouts: [StructuredWorkout], cycles: [TrainingCycle]) {
        let long = try template("Long run").instantiate()
        let micro = TrainingCycle(level: .micro, phase: .specific, loadRole: .build, name: "Micro", dateRange: day(7)...day(13), parentID: UUID())
        return ([PlannedActivity(workoutID: long.id, date: day(longRunDay))], [long], [micro])
    }

    private func rank(
        _ week: (plan: [PlannedActivity], workouts: [StructuredWorkout], cycles: [TrainingCycle]), on date: Date,
        replacing: PlannedActivity? = nil, templates: [WorkoutTemplate], microSeconds: TimeInterval? = nil, race: Race? = nil
    ) async throws -> [RankedWorkout] {
        let target = race ?? Race(name: "A race", date: day(40), priority: .primary, distanceMeters: Race.marathonDistanceMeters)
        return try await WorkoutRanker.rank(
            day: date, replacing: replacing, plan: week.plan, workouts: week.workouts, templates: templates, cycles: week.cycles,
            activities: stride(from: -42, to: 0, by: 2).map { Activity(source: .manual, sport: .running, start: day($0), duration: 3600, perceivedExertion: 1) },
            races: [target], athlete: athlete, paradigm: .triphasic, targetRace: target, microSeconds: microSeconds, today: monday
        )
    }

    @Test("a hard workout the day before the long run is short of recovery days and ranks after the ones that are not")
    func recoveryDaysShort() async throws {
        let setup = try week()
        let ranked = try await rank(setup, on: day(10), templates: [template("Easy run"), template("Short interval run")])
        let short = ranked.filter { $0.reasons.contains { if case .recoveryDaysShort = $0 { true } else { false } } }
        #expect(!short.isEmpty, "intervals the day before a long run")
        #expect(short.allSatisfy { $0.template.name == "Short interval run" })
        let firstShort = try #require(ranked.firstIndex(of: short[0]))
        #expect(ranked[..<firstShort].allSatisfy { !short.contains($0) })
        #expect(ranked.first?.reasons.contains { if case .recoveryDaysShort = $0 { true } else { false } } == false)
    }

    @Test("a workout that takes the micro above its volume says by how much")
    func aboveVolume() async throws {
        let setup = try week()
        let long = try #require(setup.workouts.first)
        let used = WorkoutDurationEstimator().duration(for: long, athlete: athlete)
        let ranked = try await rank(setup, on: day(8), templates: [template("Easy run")], microSeconds: used + 3600)
        let above = ranked.compactMap { item -> TimeInterval? in
            item.reasons.compactMap { if case .aboveMicroVolume(let by) = $0 { by } else { nil } }.first
        }
        #expect(!above.isEmpty && above.count < ranked.count, "some variants are above the volume and some are not")
        #expect(ranked.allSatisfy { $0.microSeconds == used + $0.seconds })
    }

    @Test("a day after the last planned day still counts: a bigger workout leaves a lower TSB at the end of the micro")
    func dayOutsideSeries() async throws {
        let setup = try week(longRunDay: 8)
        let ranked = try await rank(setup, on: day(12), templates: [template("Easy run")], microSeconds: 3 * 3600)
        let tsbs = try ranked.map { try #require($0.endOfMicroTSB) }
        #expect(ranked.count > 2)
        let byLoad = zip(ranked.map(\.load), tsbs).sorted { $0.0 < $1.0 }
        #expect(byLoad.first!.1 > byLoad.last!.1, "TSB \(byLoad.first!.1) with the lightest, \(byLoad.last!.1) with the heaviest")
    }

    @Test("the load override of the replaced workout is the target")
    func overrideTarget() async throws {
        var setup = try week()
        setup.plan[0].expectedLoadOverride = 80
        let ranked = try await rank(setup, on: day(11), replacing: setup.plan[0], templates: [template("Easy run"), template("Tempo run")])
        #expect(!ranked.isEmpty)
        #expect(ranked.allSatisfy { abs($0.load - 80) / 80 <= WorkoutRanker.targetMargin + 1e-9 })
    }

    @Test("no templates, no micro and no volume: an empty list, no phase reason and no micro time")
    func edges() async throws {
        var setup = try week()
        #expect(try await rank(setup, on: day(9), templates: []).isEmpty)
        setup.cycles = []
        let ranked = try await rank(setup, on: day(9), templates: [template("Easy run")])
        #expect(!ranked.isEmpty)
        #expect(ranked.allSatisfy { $0.microSeconds == nil && $0.endOfMicroTSB == nil })
        #expect(ranked.allSatisfy { !$0.reasons.contains { if case .notAskedInPhase = $0 { true } else { false } } })
    }

    @Test("a cancelled task stops the ranking")
    func cancellation() async throws {
        let setup = try week()
        let task = Task { try await rank(setup, on: day(9), templates: BuiltInWorkoutTemplates.all) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
