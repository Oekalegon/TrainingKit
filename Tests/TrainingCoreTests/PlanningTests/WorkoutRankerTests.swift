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

    private struct Fixture {
        let proposal: PlanProposal
        let activities: [Activity]
        let race: Race
    }

    /// A plan of 16 weeks for a marathon, four runs a week.
    private func fixture() async throws -> Fixture {
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

    private func rank(_ fixture: Fixture, replacing: PlannedActivity?, on date: Date, microSeconds: TimeInterval? = nil) -> [RankedWorkout] {
        let candidate = fixture.proposal.candidate
        return WorkoutRanker.rank(
            day: date, replacing: replacing, plan: candidate.plannedActivities, workouts: candidate.workouts, templates: BuiltInWorkoutTemplates.all,
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
        let ranked = rank(fixture, replacing: planned, on: planned.date)

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
        let ranked = rank(fixture, replacing: planned, on: planned.date)
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
        let ranked = rank(fixture, replacing: nil, on: date)
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
        let ranked = rank(fixture, replacing: nil, on: free, microSeconds: 6 * 3600)
        #expect(!ranked.isEmpty)
        #expect(ranked.allSatisfy { $0.microSeconds != nil })
    }
}
