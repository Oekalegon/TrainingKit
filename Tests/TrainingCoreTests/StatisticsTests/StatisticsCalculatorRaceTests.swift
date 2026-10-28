import Foundation
import Testing
@testable import TrainingCore

/// Races in the statistics (MVP5-149): a race counts like a planned activity, from today on.
@Suite("StatisticsCalculator with races")
struct StatisticsCalculatorRaceTests {
    let athlete = AthleteProfile.fixture()
    let calculator = StatisticsCalculator()
    private let start = Date(timeIntervalSince1970: 0)

    private func day(_ offset: Int) -> Date { start.addingTimeInterval(Double(offset) * 86400) }

    private func race(on offset: Int, distance: Double = 21_097.5, load: Double? = nil) -> Race {
        Race(name: "Race", date: day(offset), priority: .primary, distanceMeters: distance, expectedLoadOverride: load)
    }

    private func stats(races: [Race], activities: [Activity] = [], range: ClosedRange<Date>, today: Date) -> PeriodStats {
        calculator.periodStats(
            activities: activities, plans: [], workouts: [], races: races, athlete: athlete,
            range: range, asOf: today, previous: nil
        )
    }

    @Test("a race after today adds its distance, its load and an activity to the period it falls in")
    func futureRaceCounts() {
        let period = stats(races: [race(on: 3, load: 250)], range: day(0)...day(6), today: day(0))

        #expect(period.activityCount == 1)
        #expect(period.totalDistanceMeters == 21_097.5)
        #expect(period.totalLoad == 250)
        #expect(period.totalTime > 0)
        #expect(period.isProjected)
        #expect(period.bySport[.running]?.activityCount == 1)
    }

    @Test("without an override the load is the series' own: the same as DailyLoadSeries adds on the race day")
    func loadMatchesTheSeries() {
        let asked = race(on: 3)
        let period = stats(races: [asked], range: day(0)...day(6), today: day(0))
        let series = DailyLoadSeries().days(
            activities: [], plans: [], workouts: [], races: [asked], estimator: TRIMPPlanEstimator(),
            calculators: [ExponentialTRIMPCalculator()], athlete: athlete, today: day(0)
        )
        let raceDay = series.first { $0.load > 0 }

        #expect(period.totalLoad > 0)
        #expect(abs(period.totalLoad - (raceDay?.load ?? -1)) < 1e-9)
    }

    @Test("a race in the past adds nothing: the activity that recorded it is the record")
    func pastRaceIgnored() {
        let period = stats(races: [race(on: -2, load: 250)], range: day(-6)...day(0), today: day(0))

        #expect(period.activityCount == 0)
        #expect(period.totalLoad == 0)
    }

    @Test("a race outside the period is not counted in it")
    func raceOutsideRange() {
        let period = stats(races: [race(on: 10, load: 250)], range: day(0)...day(6), today: day(0))
        #expect(period.activityCount == 0)
    }

    @Test("on the race day itself an activity that was completed replaces the race, as it replaces a plan")
    func activityReplacesRaceToday() {
        let done = Activity(source: .manual, sport: .running, start: day(0), duration: 600, distanceMeters: 2000, perceivedExertion: 3)
        let period = stats(races: [race(on: 0, load: 250)], activities: [done], range: day(0)...day(0), today: day(0))

        #expect(period.activityCount == 1)
        #expect(period.totalDistanceMeters == 2000)
        #expect(period.totalLoad != 250)
    }

    @Test("a period with only a race today is projected")
    func raceTodayIsProjected() {
        let period = stats(races: [race(on: 0, load: 250)], range: day(0)...day(0), today: day(0))
        #expect(period.isProjected)
        #expect(period.totalLoad == 250)
    }

    @Test("the split puts the race on the planned side, and on the day it counts there even if an activity exists")
    func splitPutsRaceUnderPlanned() {
        let done = Activity(source: .manual, sport: .running, start: day(0), duration: 600, distanceMeters: 2000, perceivedExertion: 3)
        let split = calculator.periodStatsSplit(
            activities: [done], plans: [], workouts: [], races: [race(on: 0, load: 250)], athlete: athlete,
            range: day(0)...day(0), asOf: day(0)
        )

        #expect(split.actual[.running]?.activityCount == 1)
        #expect(split.planned[.running]?.activityCount == 1)
        #expect(split.planned[.running]?.load == 250)
        #expect(split.planned[.running]?.distanceMeters == 21_097.5)
    }

    @Test("weekly stats reach the week of a race after the last activity or plan")
    func weeklyStatsReachRaceWeek() throws {
        let weeks = calculator.weeklyStats(
            activities: [], plans: [], workouts: [], races: [race(on: 20, load: 250)], athlete: athlete, asOf: day(0)
        )

        let last = try #require(weeks.last)
        #expect(last.weekStart <= day(20) && day(20) < last.weekStart.addingTimeInterval(7 * 86400))
        #expect(weeks.reduce(0) { $0 + $1.totalLoad } == 250)
    }

    @Test("no races is the same as before")
    func noRacesUnchanged() {
        let with = stats(races: [], range: day(0)...day(6), today: day(0))
        #expect(with.activityCount == 0)
        #expect(with.totalLoad == 0)
    }

    @Test("a race with a pace target is timed at its goal pace; its distance is the race's own, not the pace model's")
    func paceTargetRace() {
        let asked = Race(
            name: "Half", date: day(3), priority: .primary, distanceMeters: 21_097.5,
            specificPhaseTarget: .pace(secondsPerKilometer: 300)
        )
        let period = stats(races: [asked], range: day(0)...day(6), today: day(0))

        #expect(period.totalDistanceMeters == 21_097.5)
        #expect(abs(period.totalTime - 21.0975 * 300) < 1)
        #expect(period.timeInZone.seconds.values.reduce(0, +) > 0)
        #expect(period.totalLoad > 0)
    }

    @Test("a race with a heart-rate or an effort target still counts its own distance and a duration")
    func otherTargets() {
        let targets: [SpecificPhaseTarget?] = [.heartRate(beatsPerMinute: 150...160), .perceivedEffort(6), nil, .predictedFromFitness]
        for target in targets {
            let asked = Race(name: "Race", date: day(3), priority: .primary, distanceMeters: 10_000, specificPhaseTarget: target)
            let period = stats(races: [asked], range: day(0)...day(6), today: day(0))
            #expect(period.totalDistanceMeters == 10_000, "\(String(describing: target))")
            #expect(period.totalTime > 0, "\(String(describing: target))")
        }
    }

    @Test("an athlete without heart-rate zone settings still gets the race's distance, with no time in zone and the override as load")
    func noZoneSettings() {
        var bare = athlete
        bare.heartRateZoneHistory = []
        let period = calculator.periodStats(
            activities: [], plans: [], workouts: [], races: [race(on: 3, load: 250)], athlete: bare,
            range: day(0)...day(6), asOf: day(0), previous: nil
        )

        #expect(period.totalDistanceMeters == 21_097.5)
        #expect(period.totalLoad == 250)
        #expect(period.timeInZone.seconds.values.reduce(0, +) == 0)
    }

    @Test("a race late in the evening counts on its own day in the athlete's time zone")
    func raceDayInTimeZone() {
        let amsterdam = AthleteProfile.fixture(timeZoneIdentifier: "Europe/Amsterdam")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = amsterdam.timeZone
        // 23:30 on Saturday 31 October 2026 in Amsterdam is 22:30 UTC, still the same day there, and a Sunday week start follows.
        let evening = calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 23, minute: 30))!
        let saturday = calendar.startOfDay(for: evening)
        let sunday = calendar.date(byAdding: .day, value: 1, to: saturday)!
        let asked = Race(name: "Night race", date: evening, priority: .primary, distanceMeters: 10_000, expectedLoadOverride: 100)

        func load(in range: ClosedRange<Date>) -> Double {
            calculator.periodStats(
                activities: [], plans: [], workouts: [], races: [asked], athlete: amsterdam,
                range: range, asOf: calendar.date(byAdding: .day, value: -3, to: saturday)!, previous: nil
            ).totalLoad
        }
        #expect(load(in: saturday...saturday) == 100)
        #expect(load(in: sunday...sunday) == 0)
    }

    @Test("weekly stats ignore a race in the past, as the series does")
    func weeklyStatsIgnorePastRace() {
        let weeks = calculator.weeklyStats(
            activities: [], plans: [], workouts: [], races: [race(on: -30, load: 250)], athlete: athlete, asOf: day(0)
        )
        #expect(weeks.reduce(0) { $0 + $1.totalLoad } == 0)
        #expect(weeks.count == 1)
    }

    @Test("a race in the second week shows in that week's delta against the first")
    func raceInDelta() {
        let weeks = calculator.weeklyStats(
            activities: [], plans: [], workouts: [], races: [race(on: 9, load: 250)], athlete: athlete, asOf: day(0)
        )
        let withRace = weeks.filter { $0.totalLoad > 0 }
        #expect(withRace.count == 1)
        #expect(withRace.first?.totalLoad == 250)
        #expect(withRace.first?.activityCount == 1)
    }

    @Test("a plan on the race day is counted as well: a race and a workout planned that day are two activities")
    func planOnRaceDayCountsToo() {
        let workout = StructuredWorkout(
            name: "Shakeout", sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(900), target: .heartRateZone(1))])]
        )
        let plan = PlannedActivity(workoutID: workout.id, date: day(3))
        let period = calculator.periodStats(
            activities: [], plans: [plan], workouts: [workout], races: [race(on: 3, load: 250)], athlete: athlete,
            range: day(0)...day(6), asOf: day(0), previous: nil
        )
        #expect(period.activityCount == 2)
    }
}
