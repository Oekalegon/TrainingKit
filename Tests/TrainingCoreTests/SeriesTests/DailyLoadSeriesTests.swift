import Foundation
import Testing
@testable import TrainingCore

@Suite("DailyLoadSeries")
struct DailyLoadSeriesTests {
    let athlete = AthleteProfile.fixture()
    let series = DailyLoadSeries()
    let estimator = TRIMPPlanEstimator()
    let calculators: [any LoadCalculator] = [ExponentialTRIMPCalculator(), DurationRPECalculator()]

    private func startOfDay(_ offset: Int, from reference: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: reference))!
    }

    private func steadyWorkout() -> StructuredWorkout {
        StructuredWorkout(
            name: "Steady",
            sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(1800), target: .heartRateZone(2))])]
        )
    }

    @Test("a past plan with no matching activity contributes 0")
    func pastUndonePlanContributesZero() {
        let today = startOfDay(0, from: Date())
        let workout = steadyWorkout()
        let pastPlan = PlannedActivity(workoutID: workout.id, date: startOfDay(-3, from: today))

        let days = series.days(
            activities: [], plans: [pastPlan], workouts: [workout],
            estimator: estimator, calculators: calculators, athlete: athlete, today: today
        )

        let pastDay = days.first { $0.day == startOfDay(-3, from: today) }
        #expect(pastDay?.load == 0)
        #expect(pastDay?.isProjected == false)
    }

    @Test("today with both an actual and a plan uses the actual")
    func todayPrefersActualOverPlan() {
        let today = startOfDay(0, from: Date())
        let workout = steadyWorkout()
        let plan = PlannedActivity(workoutID: workout.id, date: today)
        let hr = (0...30).map { HeartRateSample(time: today.addingTimeInterval(Double($0) * 60), bpm: 140) }
        let activity = Activity(source: .manual, sport: .running, start: today, duration: 1800, heartRate: hr)

        let days = series.days(
            activities: [activity], plans: [plan], workouts: [workout],
            estimator: estimator, calculators: calculators, athlete: athlete, today: today
        )

        let expectedActual = try! ExponentialTRIMPCalculator().load(for: activity, athlete: athlete).value
        let todayLoad = days.first { $0.day == today }
        #expect(todayLoad?.isProjected == false)
        #expect(abs(todayLoad!.load - expectedActual) < 1e-9)
    }

    @Test("a future plan is scored as an estimate")
    func futurePlanIsEstimate() {
        let today = startOfDay(0, from: Date())
        let workout = steadyWorkout()
        let futureDay = startOfDay(5, from: today)
        let plan = PlannedActivity(workoutID: workout.id, date: futureDay)

        let days = series.days(
            activities: [], plans: [plan], workouts: [workout],
            estimator: estimator, calculators: calculators, athlete: athlete, today: today
        )

        let futureLoad = days.first { $0.day == futureDay }
        #expect(futureLoad?.isProjected == true)
        #expect(futureLoad!.load > 0)
    }

    @Test("the series always extends through today, even when the last data is days away")
    func seriesAlwaysReachesToday() {
        let today = startOfDay(0, from: Date())
        let workout = steadyWorkout()
        let staleDay = startOfDay(-14, from: today)
        let hr = (0...30).map { HeartRateSample(time: staleDay.addingTimeInterval(Double($0) * 60), bpm: 140) }
        let activity = Activity(source: .manual, sport: .running, start: staleDay, duration: 1800, heartRate: hr)

        let days = series.days(
            activities: [activity], plans: [], workouts: [workout],
            estimator: estimator, calculators: calculators, athlete: athlete, today: today
        )

        #expect(days.contains { $0.day == today })
        #expect(days.last?.day == today)
        // The gap days between the stale activity and today are backfilled with 0, not skipped.
        #expect(days.count == 15)
    }

    @Test("an activity just before local midnight doesn't leak into the next day")
    func timezoneBoundaryDoesNotLeak() {
        var nonUTCAthlete = athlete
        let zone = TimeZone(identifier: "America/New_York")!
        nonUTCAthlete.timeZone = zone

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let localDayStart = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let lateNight = localDayStart.addingTimeInterval(23.5 * 3600) // 23:30 local

        let hr = [HeartRateSample(time: lateNight, bpm: 120), HeartRateSample(time: lateNight.addingTimeInterval(600), bpm: 130)]
        let activity = Activity(source: .manual, sport: .running, start: lateNight, duration: 600, heartRate: hr)
        let today = calendar.date(byAdding: .day, value: 10, to: localDayStart)!

        let days = series.days(
            activities: [activity], plans: [], workouts: [],
            estimator: estimator, calculators: calculators, athlete: nonUTCAthlete, today: today
        )

        // The series now always extends through `today` (10 days later), so this checks the
        // activity landed on `localDayStart` specifically — not that the series stops there.
        #expect(days.count == 11)
        #expect(days.first?.day == localDayStart)
        let leakedDay = localDayStart.addingTimeInterval(86400)
        #expect(!days.contains { $0.day == leakedDay && $0.load > 0 })
    }

    @Test("a race adds its estimated load on its day, whatever its priority", arguments: [RacePriority.primary, .secondary, .tertiary])
    func raceAddsLoad(priority: RacePriority) {
        let today = startOfDay(0, from: Date())
        let race = Race(name: "Race", date: startOfDay(5, from: today), priority: priority, distanceMeters: 42_195)

        let days = series.days(
            activities: [], plans: [], workouts: [], races: [race],
            estimator: estimator, calculators: calculators, athlete: athlete, today: today
        )

        let raceDay = days.first { $0.day == startOfDay(5, from: today) }
        #expect((raceDay?.load ?? 0) > 100)
        #expect(raceDay?.isProjected == true)
        #expect(days.filter { $0.day != startOfDay(5, from: today) }.allSatisfy { $0.load == 0 })
    }

    @Test("a longer race weighs more, and a pace target sets its duration")
    func raceLoadFollowsDistanceAndPace() {
        let athlete = athlete
        let marathon = Race(name: "M", date: Date(), priority: .primary, distanceMeters: 42_195)
        let ultra = Race(name: "U", date: Date(), priority: .primary, distanceMeters: 100_000)
        func load(_ race: Race) -> Double { RaceLoad.load(for: race, estimator: estimator, athlete: athlete) }
        func paced(_ seconds: Double, distance: Double = 42_195) -> Race {
            Race(name: "P", date: Date(), priority: .primary, distanceMeters: distance, specificPhaseTarget: .pace(secondsPerKilometer: seconds))
        }

        #expect(load(ultra) > load(marathon))
        // The workout takes the distance times the pace.
        let workout = RaceLoad.workout(for: paced(360), athlete: athlete)
        #expect(WorkoutDurationEstimator().duration(for: workout, athlete: athlete) == 42.195 * 360)
    }

    @Test("a pace target weighs the race by the zone of that pace, not as a zone 4 effort")
    func racePaceTargetUsesItsZone() {
        let athlete = athlete
        func load(_ race: Race) -> Double { RaceLoad.load(for: race, estimator: estimator, athlete: athlete) }
        let easy = Race(name: "E", date: Date(), priority: .primary, distanceMeters: 100_000, specificPhaseTarget: .pace(secondsPerKilometer: athlete.paceModel.secondsPerMeter(atZone: 2) * 1000))
        let hard = Race(name: "H", date: Date(), priority: .primary, distanceMeters: 100_000, specificPhaseTarget: .pace(secondsPerKilometer: athlete.paceModel.secondsPerMeter(atZone: 4) * 1000))
        let none = Race(name: "N", date: Date(), priority: .primary, distanceMeters: 100_000)

        let easyStep = RaceLoad.workout(for: easy, athlete: athlete).blocks[0].steps[0]
        #expect(easyStep.target == .heartRateZone(2))
        #expect(RaceLoad.workout(for: hard, athlete: athlete).blocks[0].steps[0].target == .heartRateZone(4))
        // Per hour an easy 100 km weighs less than an unspecified one (zone 3), a hard one more.
        func perHour(_ race: Race) -> Double {
            load(race) / (WorkoutDurationEstimator().duration(for: RaceLoad.workout(for: race, athlete: athlete), athlete: athlete) / 3600)
        }
        #expect(perHour(easy) < perHour(none))
        #expect(perHour(hard) > perHour(none))
    }

    @Test("a race counts on its own day in the athlete's time zone, on the first and last day of the series")
    func raceInAthleteTimeZone() {
        let amsterdam = AthleteProfile.fixture(timeZoneIdentifier: "Europe/Amsterdam")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = amsterdam.timeZone
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20))!
        // 00:30 local on 25 October, the night DST ends in the Netherlands: 22:30 UTC on the 24th.
        let raceStart = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 0, minute: 30))!
        let race = Race(name: "Night race", date: raceStart, priority: .primary, distanceMeters: 42_195)

        let days = series.days(
            activities: [], plans: [], workouts: [], races: [race],
            estimator: estimator, calculators: calculators, athlete: amsterdam, today: today
        )

        #expect(days.first?.day == today)
        #expect(days.last?.day == calendar.startOfDay(for: raceStart))
        #expect((days.last?.load ?? 0) > 0)
        #expect(days.dropLast().allSatisfy { $0.load == 0 })
        #expect(days.count == 6)
    }

    @Test("a race's expected load override replaces the estimate")
    func raceOverride() {
        let today = startOfDay(0, from: Date())
        let race = Race(name: "Race", date: startOfDay(2, from: today), priority: .primary, distanceMeters: 100_000, expectedLoadOverride: 1234)

        let days = series.days(
            activities: [], plans: [], workouts: [], races: [race],
            estimator: estimator, calculators: calculators, athlete: athlete, today: today
        )

        #expect(days.first { $0.day == startOfDay(2, from: today) }?.load == 1234)
    }

    @Test("a race before today adds nothing: its activity counts")
    func pastRaceAddsNothing() {
        let today = startOfDay(0, from: Date())
        let race = Race(name: "Race", date: startOfDay(-4, from: today), priority: .primary, distanceMeters: 42_195)

        let days = series.days(
            activities: [], plans: [], workouts: [], races: [race],
            estimator: estimator, calculators: calculators, athlete: athlete, today: today
        )

        #expect(days.allSatisfy { $0.load == 0 })
        #expect(days.first?.day == today)
    }

    @Test("a completed race activity counts as an activity")
    func completedRaceCounts() {
        let today = startOfDay(0, from: Date())
        let raceDay = startOfDay(-2, from: today)
        let race = Race(name: "Race", date: raceDay, priority: .primary, distanceMeters: 42_195)
        let activity = Activity(source: .manual, sport: .running, start: raceDay, duration: 4 * 3600, perceivedExertion: 8)

        let days = series.days(
            activities: [activity], plans: [], workouts: [], races: [race],
            estimator: estimator, calculators: calculators, athlete: athlete, today: today
        )

        let day = days.first { $0.day == raceDay }
        #expect((day?.load ?? 0) > 0)
        #expect(day?.isProjected == false)
    }
}
