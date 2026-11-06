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

    /// Twelve weeks of history before the plan: an hour every other day, as light as a planned easy run weighs.
    private func history(scale: Double) -> [Activity] {
        stride(from: -84, to: 0, by: 2).map { Activity(source: .manual, sport: .running, start: day($0), duration: 3600 * scale, perceivedExertion: 1) }
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

    func micros(_ candidate: PlanCandidate) -> [TrainingCycle] {
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
        asked.preferences.maxWeeklyVolume[.running] = VolumeTarget(measure: .distanceMeters, amount: 80_000)
        let roomy = try await PlanGenerator.generate(asked)
        #expect(!roomy.compromises.contains(.overriddenPreference(.maxWeeklyVolume)))

        asked.preferences.maxWeeklyVolume[.running] = VolumeTarget(measure: .distanceMeters, amount: 10_000)
        asked.startingVolume = VolumeTarget(measure: .distanceMeters, amount: 8_000)!
        asked.peakVolume = VolumeTarget(measure: .distanceMeters, amount: 10_000)!
        let tight = try await PlanGenerator.generate(asked)
        #expect(tight.compromises.contains(.overriddenPreference(.maxWeeklyVolume)))
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

    func tenDayRequest(distance: Double, spacing: Int? = nil, microLength: Int = 10) -> PlanRequest {
        let meso = MesocycleTemplate(name: "3:1", microRoles: [.build, .build, .build, .recovery], microLengthDays: microLength)
        var preferences = userPreferences
        preferences.minDaysBetweenHardSessions = spacing
        let race = Race(name: "A race", date: day(16 * microLength - 1), priority: .primary, distanceMeters: distance)
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

    // MARK: TSB zones

    @Test("point 2: a build micro ends in the training zone, a recovery micro in the recovery zone, none reaches detraining", arguments: [Race.marathonDistanceMeters, 100_000])
    func tsbZonePerMicro(distance: Double) async throws {
        // Volumes above what the zones need: the curve is a ceiling, and the plan sizes each micro under it.
        var asked = tenDayRequest(distance: distance)
        asked.startingVolume = VolumeTarget(measure: .durationSeconds, amount: 48_000)!
        asked.peakVolume = VolumeTarget(measure: .durationSeconds, amount: 72_000)!
        let candidate = try await PlanGenerator.generate(asked).candidate
        for micro in micros(candidate).dropLast() {
            let inMicro = candidate.metrics.filter { micro.dateRange.contains($0.day) }
            let end = try #require(inMicro.last)
            let expected: TSBZone = micro.loadRole == .recovery ? .recovery : .training
            #expect(end.tsbZone() == expected, "\(micro.loadRole.map(String.init(describing:)) ?? "-") micro at \(micro.dateRange.lowerBound): end TSB \(end.tsb)")
            // The day-to-day TSB still swings by several points (it jumps after a rest day), so only the end is aimed at.
            #expect(!inMicro.contains { $0.tsbZone() == .detraining }, "detraining in the micro at \(micro.dateRange.lowerBound)")
        }
    }

    @Test("point 3: TSB is in the race zone on race day and never in detraining in the last micro", arguments: [1.0, 2.0])
    func raceDayZone(scale: Double) async throws {
        var asked = tenDayRequest(distance: 100_000)
        asked.activities = history(scale: scale)
        asked.startingVolume = VolumeTarget(measure: .durationSeconds, amount: 10_800 * scale)!
        asked.peakVolume = VolumeTarget(measure: .durationSeconds, amount: 18_000 * scale)!
        let proposal = try await PlanGenerator.generate(asked)
        let last = try #require(micros(proposal.candidate).last)
        let raceDay = try #require(proposal.candidate.metrics.last { $0.day == asked.targetRace.date })
        #expect(raceDay.tsbZone() == .race, "race-day TSB \(raceDay.tsb)")
        #expect(!proposal.candidate.metrics.filter { last.dateRange.contains($0.day) }.contains { $0.tsbZone() == .detraining })
    }

    @Test("without history the curve's own volumes are used: the first weeks are warming up and have no TSB to aim at")
    func noHistoryUsesCurve() async throws {
        var asked = request(distance: Race.marathonDistanceMeters, withHistory: false)
        asked.volumeCurve = VolumeCurveBuilder()
        let candidate = try await PlanGenerator.generate(asked).candidate
        let first = try #require(micros(candidate).first)
        let seconds = candidate.sessions.filter { first.dateRange.contains($0.day) }.map(\.seconds).reduce(0, +)
        #expect(abs(seconds - 10_800) < 10_800 * 0.2, "first micro \(seconds) s")
    }

    @Test("the volume curve is a ceiling: sizing never plans more than the curve's build volume for a micro")
    func ceiling() async throws {
        var asked = tenDayRequest(distance: Race.marathonDistanceMeters)
        asked.startingVolume = VolumeTarget(measure: .durationSeconds, amount: 36_000)!
        asked.peakVolume = VolumeTarget(measure: .durationSeconds, amount: 54_000)!
        let candidate = try await PlanGenerator.generate(asked).candidate
        for micro in micros(candidate) {
            let seconds = candidate.sessions.filter { micro.dateRange.contains($0.day) }.map(\.seconds).reduce(0, +)
            #expect(seconds <= 54_000 * 10 / 7 * 1.15, "micro at \(micro.dateRange.lowerBound): \(seconds) s")
        }
    }

    @Test("the strain rule does not flag a plan that ramps up from no history")
    func strainOnRamp() async throws {
        let proposal = try await PlanGenerator.generate(request(distance: Race.marathonDistanceMeters, withHistory: false))
        #expect(!proposal.risks.contains { $0.rule == .strain })
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

    // MARK: Sizing in detail

    /// Volumes above what the zones need, so the sizing is active.
    private func generous(_ asked: PlanRequest) -> PlanRequest {
        var asked = asked
        asked.startingVolume = VolumeTarget(measure: .durationSeconds, amount: 36_000)!
        asked.peakVolume = VolumeTarget(measure: .durationSeconds, amount: 54_000)!
        return asked
    }

    func seconds(in micro: TrainingCycle, of candidate: PlanCandidate) -> Double {
        candidate.sessions.filter { micro.dateRange.contains($0.day) }.map(\.seconds).reduce(0, +)
    }

    @Test("micros of 7 and 14 days are sized too: most build micros end in training, recovery micros are about as heavy or lighter, race day is in the race zone", arguments: [7, 14])
    func microLengths(length: Int) async throws {
        let candidate = try await PlanGenerator.generate(generous(tenDayRequest(distance: Race.marathonDistanceMeters, microLength: length))).candidate
        let all = micros(candidate)
        let builds = all.dropLast().filter { $0.loadRole == .build }
        let training = builds.filter { micro in candidate.metrics.last { micro.dateRange.contains($0.day) }?.tsbZone() == .training }
        // A short micro can't always move TSB to the middle of its zone, and a template has a longest duration.
        // With hard days on Tuesday and Thursday and long runs on Saturday and Sunday the alternation run (MVP5-147) never
        // fits: a Saturday is 2 days after a hard session, which wants 3 before it, and a Sunday 2 before the next, which
        // it wants 3 after. The long runs then come from the shorter templates, which absorb less volume in a 14-day micro
        // (9 of 13 build micros end in training; the same on develop with the alternation run left out of the templates).
        // Since MVP5-158 a hard session keeps the length of its own share instead of absorbing what the easy runs cannot take
        // (an easy run tops out at 70 minutes, and the 15 hours a week asked for here are far more than a 14-day micro's runs
        // can hold): 7 of 12 end in training, so the bar is half.
        #expect(Double(training.count) >= 0.5 * Double(builds.count), "\(length)-day: \(training.count) of \(builds.count) build micros end in training")
        for (index, micro) in all.enumerated() where micro.loadRole == .recovery {
            // About as heavy or lighter than the build micro before it: its ceiling is the curve's, not the volume the build micro was
            // sized to, so a 14-day recovery micro can be a little heavier (measured: 1.11 at most).
            guard let previous = all[..<index].last(where: { $0.loadRole == .build }) else { continue }
            #expect(seconds(in: micro, of: candidate) <= seconds(in: previous, of: candidate) * 1.12, "\(length)-day recovery micro at \(micro.dateRange.lowerBound)")
        }
        #expect(try #require(candidate.metrics.last).tsbZone() == .race)
    }

    @Test("a secondary race gets its taper aimed at the race zone on its day, and the micro after it is as light as it takes")
    func secondaryRace() async throws {
        var asked = generous(tenDayRequest(distance: Race.marathonDistanceMeters))
        let other = Race(name: "B race", date: day(5 * 10 + 8), priority: .secondary, distanceMeters: 100_000)
        asked.otherRaces = [other]
        let candidate = try await PlanGenerator.generate(asked).candidate

        let raceDay = try #require(candidate.metrics.first { $0.day == other.date })
        #expect(raceDay.tsbZone() == .race, "B race day TSB \(raceDay.tsb)")
        // The 100 km leaves the following recovery micro below the recovery zone whatever it runs: it gets the
        // lightest volume, not the ceiling.
        let all = micros(candidate)
        let afterIndex = try #require(all.firstIndex { $0.dateRange.lowerBound > other.date })
        let after = all[afterIndex]
        let before = all[afterIndex - 2]
        #expect(after.loadRole == .recovery)
        #expect(seconds(in: after, of: candidate) < 0.7 * seconds(in: before, of: candidate))
    }

    @Test("the lever lowers a sized micro: the adjust loop's volume step still has an effect")
    func leverLowersSizedMicro() async throws {
        let generator = PlanGenerator(request: generous(tenDayRequest(distance: Race.marathonDistanceMeters)))
        let plain = try await generator.candidate(levers: .none, today: monday)
        let target = try #require(micros(plain)[5].dateRange.lowerBound as Date?)
        let lowered = try await generator.candidate(levers: PlanLevers(volumeScales: [target: 0.5]), today: monday)

        let before = seconds(in: micros(plain)[5], of: plain)
        let after = seconds(in: micros(lowered)[5], of: lowered)
        // Templates have shortest durations, so halving the lever does not halve the fitted seconds.
        #expect(after < 0.85 * before, "\(after) s against \(before) s")
    }

    @Test("a down week becomes a recovery micro and is sized to the recovery zone")
    func downWeekIsSized() async throws {
        let generator = PlanGenerator(request: generous(tenDayRequest(distance: Race.marathonDistanceMeters)))
        let start = try await generator.candidate(levers: .none, today: monday)
        let target = micros(start)[5].dateRange.lowerBound
        let down = try await generator.candidate(levers: PlanLevers(downWeeks: [target]), today: monday)

        let micro = micros(down)[5]
        #expect(micro.loadRole == .recovery)
        #expect(try #require(down.metrics.last { micro.dateRange.contains($0.day) }).tsbZone() == .recovery)
    }

    @Test("race day is sized in the athlete's time zone")
    func raceDayInTimeZone() async throws {
        var asked = generous(tenDayRequest(distance: Race.marathonDistanceMeters))
        asked.athlete = .fixture(timeZoneIdentifier: "Europe/Amsterdam")
        let proposal = try await PlanGenerator.generate(asked)
        #expect(try #require(proposal.candidate.metrics.last).tsbZone() == .race)
    }

    @Test("the aim uses the paradigm's guardrail overrides, like the evaluator")
    func aimFollowsOverrides() async throws {
        var asked = generous(tenDayRequest(distance: Race.marathonDistanceMeters))
        asked.paradigm.guardrailOverrides.minTSBOnRaceDay = 15
        asked.paradigm.guardrailOverrides.maxTSBOnRaceDay = 35
        let candidate = try await PlanGenerator.generate(asked).candidate
        let raceDay = try #require(candidate.metrics.last)
        // The middle of 15...35 is 25; the default zone's middle, 15, is not what it aims at.
        #expect(raceDay.tsb > 20, "race-day TSB \(raceDay.tsb)")
    }

    /// Every micro that ends in another zone than the one of its role is reported, with the zone it reached,
    /// and no other is: not one the adjust loop or a lever lowered, and not one whose aimed day is warming up.
    private func expectReports(_ candidate: PlanCandidate, levers: PlanLevers, guardrails: PlanGuardrails) throws {
        let reported = candidate.compromises.compactMap { compromise -> (Date, TSBZone, TSBZone)? in
            if case .sizingMissedZone(let start, let aimed, let reached) = compromise { (start, aimed, reached) } else { nil }
        }
        for micro in micros(candidate) {
            let start = micro.dateRange.lowerBound
            let end = try #require(candidate.metrics.last { micro.dateRange.contains($0.day) })
            let report = reported.first { $0.0 == start }
            if end.isWarmingUp || levers.volumeScale(forMicro: start) != 1 {
                #expect(report == nil, "micro at \(start) is warming up or lowered but is reported")
                continue
            }
            let aimed: TSBZone = switch micro.loadRole {
            case .build: .training
            case .recovery: .recovery
            default: .race
            }
            let zone = end.tsbZone(guardrails: guardrails)
            if zone == aimed {
                #expect(report == nil, "micro at \(start) ends in \(zone) as aimed but is reported")
            } else {
                #expect(report?.1 == aimed && report?.2 == zone, "micro at \(start) ends in \(zone), not \(aimed), and is reported as \(String(describing: report))")
            }
        }
    }

    private func guardrails(of asked: PlanRequest) -> PlanGuardrails {
        asked.paradigm.resolved(for: asked.targetRace).guardrailOverrides.applied(to: asked.guardrails)
    }

    private func missedZones(_ candidate: PlanCandidate) -> [PlanCompromise] {
        candidate.compromises.filter { if case .sizingMissedZone = $0 { true } else { false } }
    }

    @Test("a micro that ends in another zone than the one of its role is reported, and one that ends in it is not, the taper micro too", arguments: [false, true])
    func missedZoneIsReported(generousVolumes: Bool) async throws {
        // Without generous volumes the ceiling cannot reach the training zone: build micros end fresher.
        let base = tenDayRequest(distance: Race.marathonDistanceMeters)
        let asked = generousVolumes ? generous(base) : base
        let proposal = try await PlanGenerator.generate(asked)
        #expect(generousVolumes || !missedZones(proposal.candidate).isEmpty, "a plan from low volumes reports a micro that misses its zone")
        try expectReports(proposal.candidate, levers: proposal.levers, guardrails: guardrails(of: asked))
    }

    @Test("a micro whose aimed day is still warming up is not reported")
    func missedZoneNotReportedWhileWarmingUp() async throws {
        var asked = generous(tenDayRequest(distance: Race.marathonDistanceMeters))
        asked.activities = []
        let proposal = try await PlanGenerator.generate(asked)
        #expect(proposal.candidate.metrics.contains { $0.isWarmingUp })
        let first = try #require(micros(proposal.candidate).first)
        #expect(!proposal.candidate.compromises.contains { if case .sizingMissedZone(let start, _, _) = $0 { start == first.dateRange.lowerBound } else { false } })
        try expectReports(proposal.candidate, levers: proposal.levers, guardrails: guardrails(of: asked))
    }

    @Test("a micro lowered by a lever is not reported, the others are")
    func missedZoneNotReportedForLoweredMicro() async throws {
        let asked = tenDayRequest(distance: Race.marathonDistanceMeters)
        let generator = PlanGenerator(request: asked)
        let first = try await generator.candidate(levers: .none, today: monday)
        let lowered = micros(first)[5].dateRange.lowerBound
        let levers = PlanLevers(volumeScales: [lowered: 0.5])
        let candidate = try await generator.candidate(levers: levers, today: monday)
        #expect(!candidate.compromises.contains { if case .sizingMissedZone(let start, _, _) = $0 { start == lowered } else { false } })
        #expect(!missedZones(candidate).isEmpty)
        try expectReports(candidate, levers: levers, guardrails: guardrails(of: asked))
    }

    @Test("the reached zone is judged with the paradigm's guardrail overrides, like the evaluator")
    func missedZoneFollowsOverrides() async throws {
        var asked = tenDayRequest(distance: Race.marathonDistanceMeters)
        asked.paradigm.guardrailOverrides.minTSBOnRaceDay = 15
        asked.paradigm.guardrailOverrides.maxTSBOnRaceDay = 35
        let proposal = try await PlanGenerator.generate(asked)
        try expectReports(proposal.candidate, levers: proposal.levers, guardrails: guardrails(of: asked))
    }

    // MARK: Race pace and the zone of the work (MVP5-150)

    private func unresolvedSteps(_ candidate: PlanCandidate) -> [(start: Date, template: String, reason: UnresolvedReason)] {
        candidate.compromises.compactMap { compromise in
            if case .unresolvedStep(let start, let template, let reason) = compromise { (start, template, reason) } else { nil }
        }
    }

    @Test("a race pace that is a pace of a template's zone gives race-pace work without an unresolved step in the specific phase and the taper")
    func racePaceHeldByATemplate() async throws {
        var asked = generous(tenDayRequest(distance: Race.marathonDistanceMeters))
        // The fixture athlete's zone 3 runs from 249 to 273 s/km: a marathon at 270 is a zone 3 pace.
        asked.targetRace.specificPhaseTarget = .pace(secondsPerKilometer: 270)
        let candidate = try await PlanGenerator.generate(asked).candidate

        let phases = Dictionary(uniqueKeysWithValues: micros(candidate).map { ($0.dateRange.lowerBound, $0.phase) })
        let late = unresolvedSteps(candidate).filter { phases[$0.start] == .specific || phases[$0.start] == .taper }
        #expect(late.isEmpty, "\(late)")
    }

    /// The Zone 3 finish of each specific micro's long run with a fast finish, in meters, in date order.
    private func finishes(_ candidate: PlanCandidate) -> [Double] {
        let finishID = BuiltInWorkoutTemplates.longRunFastFinish.id
        let specific = micros(candidate).filter { $0.phase == .specific }
        return specific.compactMap { micro in
            candidate.plannedActivities.filter { micro.dateRange.contains($0.date) }
                .compactMap { planned in candidate.workouts.first { $0.id == planned.workoutID && $0.templateID == finishID } }
                .compactMap { $0.parameterValues?["finish"] }.first
        }
    }

    @Test("the specific phase's long run ends in a fast finish that grows from the last 3 km to the last 10 km (marathon) or 4 to 8 km (half)", arguments: [
        (Race.marathonDistanceMeters, 3_000.0, 10_000.0), (21_097.5, 4_000.0, 8_000.0),
    ])
    func fastFinishInKilometres(distance: Double, first: Double, last: Double) async throws {
        var asked = generous(tenDayRequest(distance: distance))
        asked.targetRace.specificPhaseTarget = .pace(secondsPerKilometer: 270)
        let candidate = try await PlanGenerator.generate(asked).candidate
        let finishes = finishes(candidate)
        // Every specific micro has one, and each is a multiple of the grid's step for it: no 5.33 km finish.
        #expect(finishes.count == micros(candidate).filter { $0.phase == .specific }.count, "\(finishes)")
        #expect(finishes.first == first, "\(finishes)")
        #expect(finishes.last.map { $0 <= last && $0 > first } == true, "\(finishes)")
        #expect(finishes == finishes.sorted(), "\(finishes)")
        #expect(finishes.allSatisfy { $0 >= first && $0 <= last && $0.truncatingRemainder(dividingBy: 500) == 0 }, "\(finishes)")
    }

    @Test("an ultra's long run is not forced into a fast finish at race pace")
    func noFastFinishForAnUltra() async throws {
        var asked = generous(tenDayRequest(distance: 100_000))
        asked.targetRace.specificPhaseTarget = .pace(secondsPerKilometer: 420)
        let candidate = try await PlanGenerator.generate(asked).candidate
        #expect(finishes(candidate).isEmpty)
        #expect(candidate.sessions.contains { $0.isLongRun })
    }

    @Test("with little volume the fast finish gives way and the specific micros stay close to what they are without it")
    func smallVolumeKeepsTheMicrosClose() async throws {
        func specificSeconds(withFinish: Bool) async throws -> [Double] {
            var asked = tenDayRequest(distance: Race.marathonDistanceMeters)
            asked.startingVolume = VolumeTarget(measure: .durationSeconds, amount: 5_400)!
            asked.peakVolume = VolumeTarget(measure: .durationSeconds, amount: 9_000)!
            if !withFinish { asked.paradigm.sessionProfiles[.specific] = asked.paradigm.sessionProfiles[.specific]?.filter { $0.sessionType != .long } }
            let candidate = try await PlanGenerator.generate(asked).candidate
            return micros(candidate).filter { $0.phase == .specific }.map { micro in seconds(in: micro, of: candidate) }
        }
        let with = try await specificSeconds(withFinish: true)
        let without = try await specificSeconds(withFinish: false)
        #expect(with.count == without.count)
        // The Zone 2 part of the run is at its minimum and the finish at its own, so a micro can be a little longer, not much.
        for (lhs, rhs) in zip(with, without) { #expect(lhs <= rhs * 1.15, "\(with) against \(without)") }
    }

    @Test("the fast finish keeps the hard-session spacing of the plan")
    func finishKeepsTheSpacing() async throws {
        let proposal = try await PlanGenerator.generate(generous(tenDayRequest(distance: Race.marathonDistanceMeters)))
        #expect(!proposal.evaluation.findings.contains { $0.rule == .hardSessionSpacing }, "\(proposal.evaluation.findings)")
        #expect(finishes(proposal.candidate).count == micros(proposal.candidate).filter { $0.phase == .specific }.count)
    }

    @Test("without a pace target a distance finish still gets its distance: the pace is needed only to time a step")
    func fastFinishWithoutPace() async throws {
        let candidate = try await PlanGenerator.generate(generous(tenDayRequest(distance: Race.marathonDistanceMeters))).candidate
        let finishes = finishes(candidate)
        #expect(finishes.first == 3_000 && finishes == finishes.sorted() && finishes.allSatisfy { $0 <= 10_000 }, "\(finishes)")
    }

    @Test("a race pace in no zone of any template is reported, once per template and reason in a micro")
    func racePaceOutsideEveryZone() async throws {
        var asked = generous(tenDayRequest(distance: 100_000))
        // 400 s/km is slower than every zone of the fixture athlete.
        asked.targetRace.specificPhaseTarget = .pace(secondsPerKilometer: 400)
        let candidate = try await PlanGenerator.generate(asked).candidate

        let phases = Dictionary(uniqueKeysWithValues: micros(candidate).map { ($0.dateRange.lowerBound, $0.phase) })
        let reported = unresolvedSteps(candidate).filter { phases[$0.start] == .specific }
        #expect(!reported.isEmpty)
        #expect(reported.allSatisfy { if case .paceOutsideZone = $0.reason { true } else { false } })
        let keys = reported.map { "\($0.start)|\($0.template)|\($0.reason)" }
        #expect(Set(keys).count == keys.count)
    }

    private func unresolvedPlanTargets(_ candidate: PlanCandidate) -> [UnresolvedReason] {
        candidate.compromises.compactMap { compromise in
            if case .unresolvedPlanTarget(let reason) = compromise { reason } else { nil }
        }
    }

    @Test("a plan with no race target says so once, not for every micro and template")
    func noRaceTargetIsReportedOnce() async throws {
        let asked = generous(tenDayRequest(distance: Race.marathonDistanceMeters))
        let candidate = try await PlanGenerator.generate(asked).candidate
        #expect(unresolvedPlanTargets(candidate) == [.noRaceTarget])
        #expect(!unresolvedSteps(candidate).contains { $0.reason == .noRaceTarget })
    }

    @Test("a race target that is not a pace is reported once as well")
    func unsupportedRaceTargetIsReportedOnce() async throws {
        var asked = generous(tenDayRequest(distance: Race.marathonDistanceMeters))
        asked.targetRace.specificPhaseTarget = .heartRate(beatsPerMinute: 150...160)
        let candidate = try await PlanGenerator.generate(asked).candidate
        #expect(unresolvedPlanTargets(candidate) == [.unsupportedRaceTarget])
    }

    @Test("a pace target gives no plan-level report")
    func paceTargetGivesNoPlanReport() async throws {
        var asked = generous(tenDayRequest(distance: Race.marathonDistanceMeters))
        asked.targetRace.specificPhaseTarget = .pace(secondsPerKilometer: 270)
        let candidate = try await PlanGenerator.generate(asked).candidate
        #expect(unresolvedPlanTargets(candidate).isEmpty)
    }

    @Test("open: for a zone 3 race pace no built-in template holds the structural endurance quality pace (86 % of it), so it is reported")
    func structuralEnduranceQualityIsReported() async throws {
        var asked = generous(tenDayRequest(distance: Race.marathonDistanceMeters))
        asked.targetRace.specificPhaseTarget = .pace(secondsPerKilometer: 270)
        let candidate = try await PlanGenerator.generate(asked).candidate

        let phases = Dictionary(uniqueKeysWithValues: micros(candidate).map { ($0.dateRange.lowerBound, $0.phase) })
        // Update this when a template or the fractions make the pace reachable.
        #expect(unresolvedSteps(candidate).contains { phases[$0.start] == .structural })
    }

    // MARK: Phase intensity (MVP5-153)

    @Test("race-pace work from the phase-intensity templates is in the zone of the race pace, whatever the race", arguments: [200.0, 270.0, 330.0])
    func phaseIntensityFollowsTheRacePace(racePace: Double) async throws {
        var asked = generous(tenDayRequest(distance: Race.marathonDistanceMeters))
        asked.templates = [
            BuiltInWorkoutTemplates.easyRun, BuiltInWorkoutTemplates.recoveryRun, BuiltInWorkoutTemplates.longRun,
            BuiltInWorkoutTemplates.intensityRepeats, BuiltInWorkoutTemplates.intensityBlocks,
        ]
        asked.targetRace.specificPhaseTarget = .pace(secondsPerKilometer: racePace)
        let candidate = try await PlanGenerator.generate(asked).candidate

        let phases = micros(candidate).map { (range: $0.dateRange, phase: $0.phase) }
        let workouts = Dictionary(uniqueKeysWithValues: candidate.workouts.map { ($0.id, $0) })
        let intensityIDs: Set<UUID> = [BuiltInWorkoutTemplates.intensityRepeats.id, BuiltInWorkoutTemplates.intensityBlocks.id]
        let expected = try #require(StepTargetResolver.zonePosition(forPace: racePace, in: asked.athlete.paceModel))
        var checked = 0
        for planned in candidate.plannedActivities {
            guard let workout = workouts[planned.workoutID], let templateID = workout.templateID, intensityIDs.contains(templateID),
                  phases.first(where: { $0.range.contains(planned.date) })?.phase == .specific else { continue }
            let work = try #require(workout.blocks.flatMap(\.steps).first { $0.kind == .work })
            // The specific phase asks for race pace (fraction 1.0): the target is where that pace sits in the athlete's zones.
            guard case .heartRateZoneRange(let positions)? = work.target else { Issue.record("target \(String(describing: work.target))"); return }
            // A pace outside every zone targets the whole edge zone, whose middle is 1.5 or 5.5.
            let middle = expected.exact ? expected.position : (expected.position <= 1 ? 1.5 : 5.5)
            #expect(abs((positions.lowerBound + positions.upperBound) / 2 - middle) < 0.2, "race pace \(racePace)")
            checked += 1
        }
        #expect(checked > 0)
        // A race pace outside every zone of the athlete is reported in the specific phase, a pace inside them is not.
        let reported = candidate.compromises.contains {
            if case .unresolvedStep(let start, _, _) = $0 { phases.first { $0.range.lowerBound == start }?.phase == .specific } else { false }
        }
        #expect(reported == !expected.exact)
    }

    @Test("the phase-intensity templates do not take sessions from the templates with a fixed zone in a marathon plan (MVP5-153)")
    func phaseIntensityIsOnlyAFallback() async throws {
        var asked = generous(tenDayRequest(distance: Race.marathonDistanceMeters))
        asked.templates = BuiltInWorkoutTemplates.all
        asked.targetRace.specificPhaseTarget = .pace(secondsPerKilometer: 270)
        let candidate = try await PlanGenerator.generate(asked).candidate

        let intensityIDs: Set<UUID> = [BuiltInWorkoutTemplates.intensityRepeats.id, BuiltInWorkoutTemplates.intensityBlocks.id]
        let phases = micros(candidate).map { (range: $0.dateRange, phase: $0.phase) }
        let workouts = Dictionary(uniqueKeysWithValues: candidate.workouts.map { ($0.id, $0) })
        var specific = 0
        for planned in candidate.plannedActivities {
            guard let templateID = workouts[planned.workoutID]?.templateID else { continue }
            let phase = phases.first { $0.range.contains(planned.date) }?.phase
            if phase == .specific, intensityIDs.contains(templateID) { specific += 1 }
        }
        // Where a fixed-zone template holds the race pace (the specific phase) it keeps the session; the fallback
        // only fills the structural sessions no fixed zone reaches.
        #expect(specific == 0)
    }

    // MARK: Short distances (MVP5-154)

    @Test(
        "a 5K, a 10K and a half marathon plan has no calibration warning, hard sessions in every phase from base to taper, and every session found a template",
        arguments: [(5_000.0, 230.0), (10_000.0, 245.0), (21_097.5, 260.0)]
    )
    func shortDistancePlans(distance: Double, pace: Double) async throws {
        var asked = generous(tenDayRequest(distance: distance))
        asked.templates = BuiltInWorkoutTemplates.all
        asked.targetRace.specificPhaseTarget = .pace(secondsPerKilometer: pace)
        let proposal = try await PlanGenerator.generate(asked)
        let candidate = proposal.candidate

        #expect(proposal.calibrationWarning == nil)
        let phases = micros(candidate).map { (range: $0.dateRange, phase: $0.phase) }
        let workouts = Dictionary(uniqueKeysWithValues: candidate.workouts.map { ($0.id, $0) })
        var hardByPhase: [CyclePhase: Int] = [:]
        for planned in candidate.plannedActivities {
            guard let workout = workouts[planned.workoutID], let phase = phases.first(where: { $0.range.contains(planned.date) })?.phase,
                  workout.blocks.flatMap(\.steps).contains(where: { $0.kind == .work && $0.target != nil }) else { continue }
            hardByPhase[phase, default: 0] += 1
        }
        for phase in [CyclePhase.base, .structural, .specific, .taper] {
            #expect((hardByPhase[phase] ?? 0) > 0, "\(phase.id) has no hard session")
        }
        let missing = candidate.compromises.filter { if case .missingTemplate = $0 { true } else { false } }
        #expect(missing.isEmpty)
    }

    @Test("a marathon plan is the same with and without the profiles per distance (MVP5-154)")
    func marathonIgnoresDistanceProfiles() async throws {
        var asked = generous(tenDayRequest(distance: Race.marathonDistanceMeters))
        asked.templates = BuiltInWorkoutTemplates.all
        var without = asked
        without.paradigm.distanceProfiles = [:]
        let first = try await PlanGenerator.generate(asked).candidate
        let second = try await PlanGenerator.generate(without).candidate
        func summary(_ candidate: PlanCandidate) -> [String] {
            let workouts = Dictionary(uniqueKeysWithValues: candidate.workouts.map { ($0.id, $0) })
            return candidate.plannedActivities.map { "\($0.date) \(workouts[$0.workoutID]?.name ?? "")" }
        }
        #expect(summary(first) == summary(second))
    }

    @Test("the specific-phase repeats of a 5K plan are as long as the 5K profile asks (about 3 to 4 minutes)")
    func fiveKSpecificWorkLengths() async throws {
        var asked = generous(tenDayRequest(distance: 5_000))
        asked.templates = [BuiltInWorkoutTemplates.easyRun, BuiltInWorkoutTemplates.recoveryRun, BuiltInWorkoutTemplates.longRun,
                           BuiltInWorkoutTemplates.intensityRepeats]
        asked.targetRace.specificPhaseTarget = .pace(secondsPerKilometer: 230)
        let candidate = try await PlanGenerator.generate(asked).candidate
        let phases = micros(candidate).map { (range: $0.dateRange, phase: $0.phase) }
        let workouts = Dictionary(uniqueKeysWithValues: candidate.workouts.map { ($0.id, $0) })
        var lengths: [TimeInterval] = []
        for planned in candidate.plannedActivities {
            guard let workout = workouts[planned.workoutID], workout.templateID == BuiltInWorkoutTemplates.intensityRepeats.id,
                  phases.first(where: { $0.range.contains(planned.date) })?.phase == .specific else { continue }
            for step in workout.blocks.flatMap(\.steps) where step.kind == .work {
                if case .time(let seconds) = step.goal { lengths.append(seconds) }
            }
        }
        #expect(!lengths.isEmpty)
        // The two specific profiles ask for 180 to 240 s and 60 to 90 s; the micro's position moves the length inside the range.
        #expect(lengths.allSatisfy { (60...240).contains($0) }, "\(lengths)")
    }

    // MARK: Run lengths (MVP5-158)

    @Test("a micro's runs are not all the same length: the long run is the longest and the easy runs differ")
    func runLengthsVary() async throws {
        var asked = tenDayRequest(distance: Race.marathonDistanceMeters, microLength: 7)
        asked.startingVolume = VolumeTarget(measure: .durationSeconds, amount: 21_600)!
        asked.peakVolume = VolumeTarget(measure: .durationSeconds, amount: 36_000)!
        let candidate = try await PlanGenerator.generate(asked).candidate

        var checked = 0
        var varied = 0
        for micro in micros(candidate).filter({ $0.loadRole == .build }) {
            let sessions = candidate.sessions.filter { micro.dateRange.contains($0.day) && $0.day >= asked.start }
            let long = sessions.filter(\.isLongRun).map(\.seconds)
            let easy = sessions.filter { !$0.isLongRun && $0.intensity < .high }.map(\.seconds)
            guard let longest = long.max(), easy.count >= 2 else { continue }
            checked += 1
            #expect(longest > easy.reduce(0, +) / Double(easy.count), "the long run is longer than the average easy run in the micro at \(micro.dateRange.lowerBound)")
            if Set(easy.map { Int($0 / 60) }).count > 1 { varied += 1 }
        }
        #expect(checked > 3)
        // A micro whose hard runs the adjust loop eased has equal runs (an eased run is sized like a hard one's share), so most vary, not all.
        #expect(varied * 5 >= checked * 4, "\(varied) of \(checked) micros have easy runs of different lengths")
    }
    @Test("at a volume the long run's template cannot hold, the surplus goes to the easy runs and not to the hard sessions")
    func surplusSkipsHardSessions() async throws {
        var asked = tenDayRequest(distance: Race.marathonDistanceMeters, microLength: 7)
        asked.startingVolume = VolumeTarget(measure: .durationSeconds, amount: 54_000)!
        asked.peakVolume = VolumeTarget(measure: .durationSeconds, amount: 72_000)!
        let candidate = try await PlanGenerator.generate(asked).candidate

        let hard = candidate.sessions.filter { $0.intensity >= .high && !$0.isLongRun }
        #expect(!hard.isEmpty)
        #expect(hard.allSatisfy { $0.seconds <= 120 * 60 }, "the longest hard session is \((hard.map(\.seconds).max() ?? 0) / 60) minutes")
    }
    @Test("a plan for 4 runs a week has at most 4 runs in a 7-day micro")
    func fourRunsAWeek() async throws {
        var asked = tenDayRequest(distance: Race.marathonDistanceMeters, microLength: 7)
        asked.preferences.runsPerWeek = 4
        asked.startingVolume = VolumeTarget(measure: .durationSeconds, amount: 21_600)!
        asked.peakVolume = VolumeTarget(measure: .durationSeconds, amount: 36_000)!
        let candidate = try await PlanGenerator.generate(asked).candidate

        let counts = micros(candidate).filter { $0.loadRole == .build }.map { micro in
            candidate.sessions.filter { micro.dateRange.contains($0.day) && $0.day >= asked.start }.count
        }
        #expect(counts.count > 3 && counts.allSatisfy { $0 <= 4 }, "runs per micro: \(counts)")
    }
    @Test("3 runs a week at a high volume: the runs stay within what a run can be and the sizing still reaches the TSB zones")
    func fewRunsHighVolume() async throws {
        var asked = tenDayRequest(distance: Race.marathonDistanceMeters, microLength: 7)
        asked.preferences.runsPerWeek = 3
        asked.startingVolume = VolumeTarget(measure: .durationSeconds, amount: 54_000)!
        asked.peakVolume = VolumeTarget(measure: .durationSeconds, amount: 72_000)!
        let result = try await PlanGenerator.generate(asked)

        let builds = micros(result.candidate).filter { $0.loadRole == .build }
        for micro in builds {
            let sessions = result.candidate.sessions.filter { micro.dateRange.contains($0.day) && $0.day >= asked.start }
            #expect(sessions.count <= 3)
            #expect(sessions.map(\.seconds).max() ?? 0 <= 6 * 3600, "no single run is longer than 6 hours")
        }
        let missed = result.compromises.filter { if case .sizingMissedZone = $0 { true } else { false } }
        // The sizing lowers the volume to what 3 runs can carry, so the zones are still reached (the shortfall is not lost).
        #expect(missed.count <= builds.count / 3, "micros that missed their zone: \(missed.count) of \(builds.count)")
    }
    @Test("a conditioning phase builds up from the current volume: its micros are lighter than base, which starts at the asked volume (MVP5-160)")
    func conditioningBuildsUp() async throws {
        var asked = tenDayRequest(distance: Race.marathonDistanceMeters, microLength: 7)
        asked.preferences.includeConditioning = true
        asked.targetRace.date = day(19 * 7 - 1)
        asked.macro = MacroTemplate(name: "Triphasic", mesoBlocks: [
            .init(phase: .conditioning, microCount: 3), .init(phase: .base, microCount: 3), .init(phase: .structural, microCount: 6),
            .init(phase: .specific, microCount: 6), .init(phase: .taper, microCount: 1),
        ])
        asked.startingVolume = VolumeTarget(measure: .durationSeconds, amount: 21_600)!
        asked.peakVolume = VolumeTarget(measure: .durationSeconds, amount: 36_000)!
        asked.currentVolume = VolumeTarget(measure: .durationSeconds, amount: 7_200)!
        let result = try await PlanGenerator.generate(asked)

        let conditioning = micros(result.candidate).filter { $0.phase == .conditioning && $0.loadRole == .build }
        let base = micros(result.candidate).filter { $0.phase == .base && $0.loadRole == .build }
        func seconds(_ micro: TrainingCycle) -> Double {
            result.candidate.sessions.filter { micro.dateRange.contains($0.day) && $0.day >= asked.start }.map(\.seconds).reduce(0, +)
        }
        try #require(!conditioning.isEmpty && !base.isEmpty, "the plan has a conditioning and a base phase")
        #expect(seconds(conditioning[0]) < seconds(base[0]), "the first conditioning micro is lighter than the first base micro")
        #expect(seconds(conditioning[0]) <= 21_600 * 0.6, "conditioning starts near the current volume, not the base volume")
    }
    @Test("a weekly maximum below the start lowers the start, and a higher current volume does not push conditioning above it (MVP5-160)")
    func conditioningUnderWeeklyMaximum() async throws {
        var asked = tenDayRequest(distance: Race.marathonDistanceMeters, microLength: 7)
        asked.preferences.includeConditioning = true
        asked.preferences.maxWeeklyVolume[.running] = VolumeTarget(measure: .durationSeconds, amount: 14_400)!
        asked.targetRace.date = day(19 * 7 - 1)
        asked.macro = MacroTemplate(name: "Triphasic", mesoBlocks: [
            .init(phase: .conditioning, microCount: 3), .init(phase: .base, microCount: 3), .init(phase: .structural, microCount: 6),
            .init(phase: .specific, microCount: 6), .init(phase: .taper, microCount: 1),
        ])
        asked.startingVolume = VolumeTarget(measure: .durationSeconds, amount: 21_600)!
        asked.peakVolume = VolumeTarget(measure: .durationSeconds, amount: 36_000)!
        asked.currentVolume = VolumeTarget(measure: .durationSeconds, amount: 18_000)!
        let result = try await PlanGenerator.generate(asked)

        func seconds(_ micro: TrainingCycle) -> Double {
            result.candidate.sessions.filter { micro.dateRange.contains($0.day) && $0.day >= asked.start }.map(\.seconds).reduce(0, +)
        }
        let conditioning = micros(result.candidate).filter { $0.phase == .conditioning && $0.loadRole == .build }
        #expect(!conditioning.isEmpty)
        #expect(conditioning.allSatisfy { seconds($0) <= 14_400 * 1.05 }, "conditioning stays at the weekly maximum")
    }
    // MARK: Special blocks (MVP5-161)

    @Test("blocks go in the latest specific build micros with one micro after them, at least three apart")
    func blockPlacement() {
        func micro(_ phase: CyclePhase, _ role: MicroLoadRole, _ index: Int) -> Microcycle {
            Microcycle(dateRange: day(index * 7)...day(index * 7 + 6), phase: phase, loadRole: role, mesoBlockIndex: 0)
        }
        let plan = (0..<3).map { micro(.base, .build, $0) } + (3..<12).map { micro(.specific, $0 % 4 == 0 ? .recovery : .build, $0) } + [micro(.taper, .taper, 12)]
        #expect(PlanGenerator.specialBlockMicros(plan, wanted: 1) == [11])
        #expect(PlanGenerator.specialBlockMicros(plan, wanted: 2) == [11, 7])
        let two = PlanGenerator.specialBlockMicros(plan, wanted: 2).sorted()
        #expect(two.count == 2 && two[1] - two[0] >= 3)
        #expect(PlanGenerator.specialBlockMicros(plan, wanted: 0).isEmpty)
        #expect(PlanGenerator.specialBlockMicros(Array(plan.prefix(5)), wanted: 1) == [3])
        #expect(PlanGenerator.specialBlockMicros(Array(plan.prefix(3)), wanted: 1).isEmpty, "no specific phase, no block")
    }

    @Test("a marathon plan with one block has one day with two sessions, in the specific phase")
    func marathonBlock() async throws {
        var asked = tenDayRequest(distance: Race.marathonDistanceMeters, microLength: 7)
        asked.preferences.specialBlocks = 1
        for weekday in [Weekday.tuesday, .thursday] { asked.preferences.runAvailability[weekday] = [.morning, .evening] }
        asked.startingVolume = VolumeTarget(measure: .durationSeconds, amount: 21_600)!
        asked.peakVolume = VolumeTarget(measure: .durationSeconds, amount: 36_000)!
        let result = try await PlanGenerator.generate(asked)

        let specific = micros(result.candidate).filter { $0.phase == .specific }
        // Intensity is not the test of a hard session here (the fitter can give a hard run a low-intensity template): two sessions in a day are.
        let doubles = specific.filter { micro in
            Dictionary(grouping: result.candidate.sessions.filter { micro.dateRange.contains($0.day) }, by: \.day).values.contains { $0.count == 2 }
        }
        #expect(doubles.count == 1, "one specific micro has two sessions in a day")
        let doubleDay = doubles.first.flatMap { micro in
            Dictionary(grouping: result.candidate.sessions.filter { micro.dateRange.contains($0.day) }, by: \.day).first { $0.value.count == 2 }?.key
        }
        #expect(!result.compromises.contains { if case .recoveryDaysShort(let day, _, _, _) = $0 { day == doubleDay } else { false } },
                "the two sessions of the block's day do not ask days of each other")
        #expect(micros(result.candidate).filter { $0.phase != .specific }.allSatisfy { micro in
            Dictionary(grouping: result.candidate.sessions.filter { micro.dateRange.contains($0.day) }, by: \.day).values.allSatisfy { $0.count == 1 }
        }, "no other micro has a double day")
        #expect(result.candidate.sessions.filter(\.isBlockSession).map(\.day) == doubleDay.map { [$0] } ?? [], "the second session of the block's day is marked")
        #expect(!result.proposalFindingsOnBlockDay(doubleDay), "the evaluator does not fault the block's day")
        #expect(!result.compromises.contains { if case .overriddenPreference(.specialBlocks) = $0 { true } else { false } })
    }

    @Test("an ultra plan with one block has long runs on two consecutive days in one micro, and a request that cannot fit is reported")
    func ultraBlock() async throws {
        var asked = tenDayRequest(distance: 100_000, microLength: 7)
        asked.preferences.specialBlocks = 1
        asked.startingVolume = VolumeTarget(measure: .durationSeconds, amount: 21_600)!
        asked.peakVolume = VolumeTarget(measure: .durationSeconds, amount: 36_000)!
        let result = try await PlanGenerator.generate(asked)
        let pairs = micros(result.candidate).filter { micro in
            let days = result.candidate.sessions.filter { micro.dateRange.contains($0.day) && $0.isLongRun }.map(\.day).sorted()
            return zip(days, days.dropFirst()).contains { $1.timeIntervalSince($0) < 1.5 * 86_400 }
        }
        #expect(pairs.count == 1)

        var impossible = asked
        impossible.preferences.specialBlocks = 2
        impossible.macro = MacroTemplate(name: "Short", mesoBlocks: [.init(phase: .base, microCount: 3), .init(phase: .specific, microCount: 2), .init(phase: .taper, microCount: 1)])
        impossible.targetRace.date = day(6 * 7 - 1)
        let short = try await PlanGenerator.generate(impossible)
        #expect(short.compromises.contains { if case .overriddenPreference(.specialBlocks) = $0 { true } else { false } })
    }
}

private extension PlanProposal {
    /// Whether the evaluation holds a spacing or per-micro finding dated on `day`.
    func proposalFindingsOnBlockDay(_ day: Date?) -> Bool {
        guard let day else { return false }
        return evaluation.findings.contains { ($0.rule == .hardSessionSpacing || $0.rule == .hardSessionsPerMicro) && $0.day == day }
    }
}
