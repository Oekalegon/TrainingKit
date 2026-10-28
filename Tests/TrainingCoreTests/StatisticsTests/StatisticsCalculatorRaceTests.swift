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
}
