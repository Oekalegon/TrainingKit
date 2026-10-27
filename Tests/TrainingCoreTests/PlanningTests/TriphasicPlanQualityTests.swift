import Foundation
import Testing
@testable import TrainingCore

/// Reproduction of the first real triphasic plan (fix/triphasic-plan-quality): one test per reported
/// problem, each a regression test once the fix is in.
@Suite("Triphasic plan quality")
struct TriphasicPlanQualityTests {
    private let athlete = AthleteProfile.fixture()
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private var monday: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 26))! }
    private func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: monday)! }

    private let macro = MacroTemplate(name: "Triphasic", mesoBlocks: [
        .init(phase: .base, microCount: 3), .init(phase: .structural, microCount: 6),
        .init(phase: .specific, microCount: 6), .init(phase: .taper, microCount: 1),
    ])

    /// Tuesday, Thursday, Saturday and Sunday, one run each.
    private var fourRuns: PlanPreferences {
        var availability = RunAvailability()
        for weekday in [Weekday.tuesday, .thursday, .saturday, .sunday] { availability[weekday] = [.morning] }
        return PlanPreferences(runAvailability: availability)
    }

    /// Twelve weeks of history before the plan: an hour every other day.
    private func history(scale: Double) -> [Activity] {
        stride(from: -84, to: 0, by: 2).map { Activity(source: .manual, sport: .running, start: day($0), duration: 3600 * scale, perceivedExertion: 5) }
    }

    /// `scale` multiplies the history and the plan's volumes: 1 is a 3 to 5 hour week, 2 a 6 to 10 hour one.
    private func request(distance: Double, scale: Double = 1, withHistory: Bool = true) -> PlanRequest {
        let race = Race(name: "A race", date: day(16 * 7 - 1), priority: .primary, distanceMeters: distance)
        var request = PlanRequest(
            targetRace: race, paradigm: .triphasic, macro: macro, meso: .threeToOne, preferences: fourRuns, athlete: athlete,
            today: monday, start: monday, templates: BuiltInWorkoutTemplates.all,
            startingVolume: VolumeTarget(measure: .durationSeconds, amount: 10_800 * scale)!,
            peakVolume: VolumeTarget(measure: .durationSeconds, amount: 18_000 * scale)!
        )
        request.activities = withHistory ? history(scale: scale) : []
        return request
    }

    private func micros(_ candidate: PlanCandidate) -> [TrainingCycle] {
        candidate.cycles.filter { $0.level == .micro }.sorted { $0.dateRange.lowerBound < $1.dateRange.lowerBound }
    }

    @Test("point 4: nothing is planned on race day", arguments: [Race.marathonDistanceMeters, 100_000])
    func nothingOnRaceDay(distance: Double) async throws {
        let candidate = try await PlanGenerator.generate(request(distance: distance)).candidate
        #expect(!candidate.plannedActivities.contains { $0.date == day(16 * 7 - 1) })
    }

    @Test("point 5: the target race adds its load on race day, and no run does")
    func raceLoad() async throws {
        let asked = request(distance: 100_000)
        let candidate = try await PlanGenerator.generate(asked).candidate
        let raceDay = try #require(candidate.metrics.last)
        #expect(raceDay.day == day(16 * 7 - 1))
        #expect(raceDay.load == RaceLoad.load(for: asked.targetRace, estimator: TRIMPPlanEstimator(), athlete: athlete))
        #expect(raceDay.load > candidate.metrics.dropLast().map(\.load).max()!)
    }

    @Test("the day after a 100 km race the athlete is in the injury risk zone")
    func riskAfterUltra() throws {
        let race = Race(name: "100K", date: day(10), priority: .primary, distanceMeters: 100_000)
        let days = DailyLoadSeries().days(
            activities: history(scale: 1), plans: [], workouts: [], races: [race],
            estimator: TRIMPPlanEstimator(), calculators: [DurationRPECalculator()], athlete: athlete, today: monday
        )
        let padded = days + (1...3).map { DayLoad(day: day(10 + $0), load: 0, isProjected: true) }
        let metrics = FitnessMetricsCalculator().metrics(for: padded, parameters: LoadModelParameters(), seed: nil)
        let after = try #require(metrics.first { $0.day == day(11) })
        #expect(after.tsbZone() == .injuryRisk, "TSB \(after.tsb)")
    }

    @Test("the other races add load on their day too, whatever their priority", arguments: [RacePriority.secondary, .tertiary])
    func otherRaceLoad(priority: RacePriority) async throws {
        var asked = request(distance: Race.marathonDistanceMeters)
        let other = Race(name: "Other", date: day(8 * 7 + 2), priority: priority, distanceMeters: 21_097.5)
        asked.otherRaces = [other]
        let candidate = try await PlanGenerator.generate(asked).candidate
        let metric = try #require(candidate.metrics.first { $0.day == other.date })
        #expect(metric.load == RaceLoad.load(for: other, estimator: TRIMPPlanEstimator(), athlete: athlete))
        #expect(!candidate.plannedActivities.contains { $0.date == other.date })
    }

    @Test("starting and peak volume can be a distance, planned as the same duration at the easy pace")
    func distanceVolume() async throws {
        let easy = athlete.paceModel.secondsPerMeter(atZone: 2)
        var asked = request(distance: Race.marathonDistanceMeters)
        asked.startingVolume = VolumeTarget(measure: .distanceMeters, amount: 10_800 / easy)!
        asked.peakVolume = VolumeTarget(measure: .distanceMeters, amount: 18_000 / easy)!
        let byDistance = try await PlanGenerator.generate(asked).candidate

        let bySeconds = try await PlanGenerator.generate(request(distance: Race.marathonDistanceMeters)).candidate
        #expect(!byDistance.plannedActivities.isEmpty)
        #expect(byDistance.sessions.map(\.seconds).map { $0.rounded() } == bySeconds.sessions.map(\.seconds).map { $0.rounded() })
    }

    @Test("a TRIMP volume is still not supported")
    func trimpVolume() async throws {
        var asked = request(distance: Race.marathonDistanceMeters)
        asked.peakVolume = VolumeTarget(measure: .trimp, amount: 500)!
        await #expect(throws: PlanGeneratorError.unsupportedVolumeMeasure(.trimp)) { try await PlanGenerator.generate(asked) }
    }

    @Test("a maximum weekly distance is compared with the plan in the same measure")
    func weeklyDistanceLimit() async throws {
        let easy = athlete.paceModel.secondsPerMeter(atZone: 2)
        var asked = request(distance: Race.marathonDistanceMeters)
        asked.startingVolume = VolumeTarget(measure: .distanceMeters, amount: 10_800 / easy)!
        asked.peakVolume = VolumeTarget(measure: .distanceMeters, amount: 18_000 / easy)!
        asked.preferences.maxWeeklyVolume[.running] = VolumeTarget(measure: .distanceMeters, amount: 50_000)
        let proposal = try await PlanGenerator.generate(asked)
        #expect(!proposal.compromises.contains(.overriddenPreference(.maxWeeklyVolume)))
    }

    // MARK: Target workouts (the user's setup: 10-day micros, Tuesday and Thursday for hard sessions, Saturday and Sunday for long runs)

    private var userPreferences: PlanPreferences {
        var availability = RunAvailability()
        for weekday in [Weekday.tuesday, .thursday, .saturday, .sunday] { availability[weekday] = [.morning] }
        availability.setRunTypes([.interval, .threshold, .easy], on: .tuesday)
        availability.setRunTypes([.interval, .threshold, .easy], on: .thursday)
        availability.setRunTypes([.long, .easy], on: .saturday)
        availability.setRunTypes([.long, .easy], on: .sunday)
        return PlanPreferences(runAvailability: availability)
    }

    private func tenDayRequest(distance: Double, spacing: Int? = nil) -> PlanRequest {
        let meso = MesocycleTemplate(name: "3:1", microRoles: [.build, .build, .build, .recovery], microLengthDays: 10)
        var preferences = userPreferences
        preferences.minDaysBetweenHardSessions = spacing
        let race = Race(name: "A race", date: day(16 * 10 - 1), priority: .primary, distanceMeters: distance)
        var asked = PlanRequest(
            targetRace: race, paradigm: .triphasic, macro: macro, meso: meso, preferences: preferences, athlete: athlete,
            today: monday, start: monday, templates: BuiltInWorkoutTemplates.all,
            startingVolume: VolumeTarget(measure: .durationSeconds, amount: 10_800)!,
            peakVolume: VolumeTarget(measure: .durationSeconds, amount: 18_000)!
        )
        asked.activities = history(scale: 1)
        return asked
    }

    @Test("point 1: every micro has target workouts; the only sessions left out are hard ones the Tuesday and Thursday cannot hold", arguments: [Race.marathonDistanceMeters, 100_000])
    func targetWorkouts(distance: Double) async throws {
        let asked = tenDayRequest(distance: distance)
        #expect(asked.hardSessionsPerMicro == 3)
        let proposal = try await PlanGenerator.generate(asked)
        #expect(!proposal.compromises.contains { if case .missingTemplate = $0 { true } else { false } })
        for case .unplacedSession(_, let dropped) in proposal.compromises {
            // A 10-day micro holds two to four Tuesdays and Thursdays, the only days that allow a hard session.
            #expect(dropped.kind == .hard && dropped.reason == .runTypeNotAllowed)
        }

        let workouts = Dictionary(uniqueKeysWithValues: proposal.candidate.workouts.map { ($0.id, $0) })
        let hardTypes: Set<SessionType> = [.interval, .tempo, .hillRepeats]
        for micro in micros(proposal.candidate) where [CyclePhase.base, .structural, .specific].contains(micro.phase) {
            let targets = proposal.candidate.plannedActivities
                .filter { micro.dateRange.contains($0.date) }
                .compactMap { workouts[$0.workoutID]?.sessionType }
                .filter(hardTypes.contains)
            #expect(targets.count >= 2, "\(micro.phase.id) micro at \(micro.dateRange.lowerBound): \(targets.count) target workouts")
        }
        #expect(!proposal.risks.contains { $0.rule == .hardSessionSpacing })
    }

    @Test("base micros plan hill sprints, structural micros a fast and an endurance quality session")
    func profilesTakeEffect() async throws {
        let candidate = try await PlanGenerator.generate(tenDayRequest(distance: 100_000)).candidate
        let workouts = Dictionary(uniqueKeysWithValues: candidate.workouts.map { ($0.id, $0) })
        func types(_ phase: CyclePhase) -> Set<SessionType> {
            Set(micros(candidate).filter { $0.phase == phase }.flatMap { micro in
                candidate.plannedActivities.filter { micro.dateRange.contains($0.date) }.compactMap { workouts[$0.workoutID]?.sessionType }
            })
        }
        #expect(types(.base).contains(.hillRepeats))
        #expect(types(.structural).contains(.interval))
        let structural = micros(candidate).first { $0.phase == .structural }!
        let names = candidate.plannedActivities.filter { structural.dateRange.contains($0.date) }.compactMap { workouts[$0.workoutID] }
        #expect(names.filter { $0.sessionType == .interval }.count >= 2)
    }

    @Test("the plan's spacing replaces the paradigm's: with 3 days no two hard sessions are closer")
    func spacingOverride() async throws {
        for spacing in [2, 3] {
            let candidate = try await PlanGenerator.generate(tenDayRequest(distance: Race.marathonDistanceMeters, spacing: spacing)).candidate
            let hard = candidate.sessions.filter { $0.intensity >= .high || $0.speed == .max || $0.isLongRun }.map(\.day).sorted()
            let gaps = zip(hard, hard.dropFirst()).map { calendar.dateComponents([.day], from: $0, to: $1).day! }
            #expect(gaps.allSatisfy { $0 >= spacing }, "spacing \(spacing): gaps \(gaps)")
        }
    }

    // MARK: Race-target fractions reach the steps

    /// The fractions of race pace (250 s/km) the work steps of the structural interval sessions were given,
    /// per micro, with a Z5 interval template so that fast quality's 1.14 to 1.06 can fall in its zone.
    private func structuralFractions(hardSessions: Int? = nil) async throws -> [[Double]] {
        var asked = tenDayRequest(distance: Race.marathonDistanceMeters)
        asked.targetRace.specificPhaseTarget = .pace(secondsPerKilometer: 250)
        asked.templates = [BuiltInWorkoutTemplates.easyRun, BuiltInWorkoutTemplates.longRun, BuiltInWorkoutTemplates.shortIntervalRunTrack]
        if let hardSessions { asked.hardSessionsPerMicro = hardSessions }
        let candidate = try await PlanGenerator.generate(asked).candidate
        let workouts = Dictionary(uniqueKeysWithValues: candidate.workouts.map { ($0.id, $0) })
        var result: [[Double]] = []
        for micro in micros(candidate) where micro.phase == .structural {
            var fractions: [Double] = []
            for planned in candidate.plannedActivities where micro.dateRange.contains(planned.date) {
                guard let workout = workouts[planned.workoutID], workout.sessionType == .interval else { continue }
                for step in workout.blocks.flatMap(\.steps) where step.kind == .work {
                    if case .pace(let range)? = step.companionTarget {
                        fractions.append(250 / ((range.lowerBound + range.upperBound) / 2))
                    }
                }
            }
            result.append(fractions)
        }
        return result
    }

    @Test("the fast and endurance quality fractions drift across the structural phase and reach the steps")
    func fractionsReachSteps() async throws {
        let perMicro = try await structuralFractions()
        let all = perMicro.flatMap { $0 }
        #expect(perMicro.first?.contains { abs($0 - 1.14) < 0.003 } == true, "first micro \(perMicro.first ?? [])")
        #expect(perMicro.first?.contains { abs($0 - 0.86) < 0.003 } == true)
        #expect(all.contains { $0 > 1.07 && $0 < 1.12 }, "a fast fraction part-way down: \(all)")
        #expect(all.contains { $0 > 0.88 && $0 < 0.92 }, "an endurance fraction part-way up: \(all)")
    }

    @Test("a micro with a single hard run alternates between fast and endurance quality")
    func singleHardRunAlternates() async throws {
        let perMicro = try await structuralFractions(hardSessions: 1)
        let fast = perMicro.filter { $0.contains { $0 > 1.05 && $0 < 1.15 } }.count
        let endurance = perMicro.filter { $0.contains { $0 > 0.85 && $0 < 0.95 } }.count
        #expect(fast > 0 && endurance > 0, "fast in \(fast) micros, endurance in \(endurance)")
    }

    @Test("a plan's spacing applies to a paradigm that has none of its own")
    func overrideOnParadigmWithoutSpacing() async throws {
        var asked = tenDayRequest(distance: Race.marathonDistanceMeters, spacing: 3)
        asked.paradigm.minDaysBetweenHardSessions = nil
        let candidate = try await PlanGenerator.generate(asked).candidate
        let hard = candidate.sessions.filter { $0.intensity >= .high || $0.speed == .max || $0.isLongRun }.map(\.day).sorted()
        let gaps = zip(hard, hard.dropFirst()).map { calendar.dateComponents([.day], from: $0, to: $1).day! }
        #expect(gaps.allSatisfy { $0 >= 3 }, "gaps \(gaps)")
    }
}
