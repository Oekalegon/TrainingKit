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

    private func tenDayRequest(distance: Double, spacing: Int? = nil, microLength: Int = 10) -> PlanRequest {
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
        asked.startingVolume = VolumeTarget(measure: .durationSeconds, amount: 36_000)!
        asked.peakVolume = VolumeTarget(measure: .durationSeconds, amount: 54_000)!
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

    private func seconds(in micro: TrainingCycle, of candidate: PlanCandidate) -> Double {
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
        #expect(Double(training.count) >= 0.65 * Double(builds.count), "\(length)-day: \(training.count) of \(builds.count) build micros end in training")
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

    @Test("a micro that ends in another zone than the one of its role is reported, and one that ends in it is not", arguments: [false, true])
    func missedZoneIsReported(generousVolumes: Bool) async throws {
        // Without generous volumes the ceiling cannot reach the training zone: build micros end fresher.
        let base = tenDayRequest(distance: Race.marathonDistanceMeters)
        let proposal = try await PlanGenerator.generate(generousVolumes ? generous(base) : base)
        let candidate = proposal.candidate
        let reported = candidate.compromises.compactMap { compromise -> (Date, TSBZone, TSBZone)? in
            if case .sizingMissedZone(let start, let aimed, let reached) = compromise { (start, aimed, reached) } else { nil }
        }
        #expect(generousVolumes || !reported.isEmpty, "a plan from low volumes reports no micro that misses its zone")

        for micro in micros(candidate).dropLast() where proposal.levers.volumeScale(forMicro: micro.dateRange.lowerBound) == 1 {
            let endZone = try #require(candidate.metrics.last { micro.dateRange.contains($0.day) }).tsbZone()
            let aimed: TSBZone = micro.loadRole == .recovery ? .recovery : .training
            let report = reported.first { $0.0 == micro.dateRange.lowerBound }
            // Warming up (no history to aim from) is not reported; the history here covers it.
            if endZone == aimed {
                #expect(report == nil, "micro at \(micro.dateRange.lowerBound) ends in \(endZone) as aimed but is reported")
            } else {
                #expect(report?.1 == aimed && report?.2 == endZone, "micro at \(micro.dateRange.lowerBound) ends in \(endZone), not \(aimed), and is reported as \(String(describing: report))")
            }
        }
    }
}
