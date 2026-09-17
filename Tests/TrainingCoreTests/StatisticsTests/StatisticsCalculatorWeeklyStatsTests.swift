import Foundation
import Testing
@testable import TrainingCore

@Suite("StatisticsCalculator.weeklyStats")
struct StatisticsCalculatorWeeklyStatsTests {
    private func athlete(timeZoneIdentifier: String = "UTC") -> AthleteProfile {
        AthleteProfile.fixture(timeZoneIdentifier: timeZoneIdentifier)
    }

    private func activity(start: Date, distanceMeters: Double, duration: TimeInterval, perceivedExertion: Int = 5) -> Activity {
        Activity(source: .manual, sport: .running, start: start, duration: duration, distanceMeters: distanceMeters, perceivedExertion: perceivedExertion)
    }

    @Test("delta is nil on the first week")
    func deltaNilOnFirstWeek() {
        let athlete = athlete()
        // Monday 2024-01-01 00:00 UTC.
        let monday = Date(timeIntervalSince1970: 1_704_067_200)
        let activities = [activity(start: monday, distanceMeters: 5000, duration: 1800)]
        let calculator = StatisticsCalculator()

        let weeks = calculator.weeklyStats(activities: activities, plans: [], workouts: [], athlete: athlete, asOf: monday)

        #expect(weeks.first?.delta == nil)
    }

    @Test("delta fraction is guarded to 0 when the previous week's total was 0")
    func deltaGuardedAgainstZeroPrevious() {
        let athlete = athlete()
        let firstMonday = Date(timeIntervalSince1970: 1_704_067_200) // 2024-01-01
        let secondMonday = firstMonday.addingTimeInterval(7 * 86400) // 2024-01-08
        // A past plan with no matching activity contributes 0 (same rule as DailyLoadSeries) and
        // exists only to anchor the first week in the output; the real activity is dated on
        // `today` itself, so the second week's total is real.
        let pastPlan = PlannedActivity(workoutID: UUID(), date: firstMonday)
        let activities = [activity(start: secondMonday, distanceMeters: 5000, duration: 1800)]
        let calculator = StatisticsCalculator()

        let weeks = calculator.weeklyStats(activities: activities, plans: [pastPlan], workouts: [], athlete: athlete, asOf: secondMonday)

        #expect(weeks.count == 2)
        #expect(weeks[0].totalDistanceMeters == 0)
        let secondWeek = weeks[1]
        #expect(secondWeek.delta != nil)
        #expect(secondWeek.delta?.distanceFraction == 0)
        #expect(secondWeek.delta?.distanceMeters == 5000)
    }

    @Test("an actual activity dated after today is excluded, matching DailyLoadSeries")
    func futureActualActivityExcluded() {
        let athlete = athlete()
        let firstMonday = Date(timeIntervalSince1970: 1_704_067_200) // 2024-01-01
        let secondMonday = firstMonday.addingTimeInterval(7 * 86400) // 2024-01-08
        // Replaying "as of firstMonday" against a store that already has a later activity: that
        // activity must not count as actual, or this descriptive view would silently disagree
        // with DailyLoadSeries/FitnessMetricsCalculator about what happened by `today`.
        let futureActivity = activity(start: secondMonday, distanceMeters: 5000, duration: 1800)

        let weeks = StatisticsCalculator().weeklyStats(activities: [futureActivity], plans: [], workouts: [], athlete: athlete, asOf: firstMonday)

        #expect(weeks.count == 2)
        #expect(weeks[1].totalDistanceMeters == 0)
        #expect(weeks[1].activityCount == 0)
    }

    @Test("week assignment respects the athlete's timezone at the boundary")
    func weekBoundaryRespectsTimeZone() {
        let athlete = athlete(timeZoneIdentifier: "America/Los_Angeles") // UTC-8 in January
        // 2024-01-07 23:00 America/Los_Angeles (still Sunday locally) is 2024-01-08 07:00 UTC
        // (already Monday in UTC) — the week assignment must follow the local day, not UTC.
        let sundayNightLocal = Date(timeIntervalSince1970: 1_704_697_200)
        let activities = [activity(start: sundayNightLocal, distanceMeters: 5000, duration: 1800)]
        let calculator = StatisticsCalculator()
        let today = sundayNightLocal.addingTimeInterval(86400)

        let weeks = calculator.weeklyStats(activities: activities, plans: [], workouts: [], athlete: athlete, asOf: today)

        // Weekday default is Monday; the activity should land in the week starting Monday 2024-01-01,
        // not the week starting Monday 2024-01-08.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = athlete.timeZone
        let expectedWeekStart = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_704_096_000)) // 2024-01-01 local
        #expect(weeks.first?.weekStart == expectedWeekStart)
        #expect(weeks.first?.totalDistanceMeters == 5000)
    }

    @Test("a future week is projected from planned activities")
    func futureWeekIsProjected() {
        let athlete = athlete()
        let monday = Date(timeIntervalSince1970: 1_704_067_200)
        let nextMonday = monday.addingTimeInterval(7 * 86400)
        let workout = StructuredWorkout(
            name: "Easy run",
            sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(1800), target: .heartRateZone(2))])]
        )
        let plan = PlannedActivity(workoutID: workout.id, date: nextMonday)
        let calculator = StatisticsCalculator()

        let weeks = calculator.weeklyStats(activities: [], plans: [plan], workouts: [workout], athlete: athlete, asOf: monday)

        let nextWeek = weeks.last
        #expect(nextWeek?.isProjected == true)
        #expect(nextWeek?.activityCount == 1)
        #expect((nextWeek?.totalLoad ?? 0) > 0)
    }

    @Test("a partial current week mixes an earlier actual activity with a later planned activity")
    func partialCurrentWeekMixesActualAndPlanned() {
        let athlete = athlete()
        let monday = Date(timeIntervalSince1970: 1_704_067_200) // 2024-01-01
        let wednesday = monday.addingTimeInterval(2 * 86400)
        let friday = monday.addingTimeInterval(4 * 86400)

        let pastActivity = activity(start: monday, distanceMeters: 5000, duration: 1800)
        let workout = StructuredWorkout(
            name: "Easy run",
            sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(1800), target: .heartRateZone(2))])]
        )
        let futurePlan = PlannedActivity(workoutID: workout.id, date: friday)
        let calculator = StatisticsCalculator()

        // `asOf: wednesday` puts the week's Monday in the past (actual) and its Friday in the
        // future (planned) — the same week's stats must reflect both, not just whichever side of
        // `today` happens to be checked first.
        let weeks = calculator.weeklyStats(activities: [pastActivity], plans: [futurePlan], workouts: [workout], athlete: athlete, asOf: wednesday)

        #expect(weeks.count == 1)
        let week = weeks[0]
        #expect(week.isProjected == true)
        #expect(week.activityCount == 2)
        #expect(week.totalDistanceMeters > 5000) // the actual 5000 m plus the plan's projected distance
        #expect(week.totalTime == 3600) // 1800 s actual + 1800 s planned
    }
}
