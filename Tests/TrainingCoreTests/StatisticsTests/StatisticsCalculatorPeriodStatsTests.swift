import Foundation
import Testing
@testable import TrainingCore

@Suite("StatisticsCalculator.periodStats")
struct StatisticsCalculatorPeriodStatsTests {
    let athlete = AthleteProfile.fixture()
    let calculator = StatisticsCalculator()

    private func activity(sport: Sport, start: Date, distanceMeters: Double, duration: TimeInterval, perceivedExertion: Int = 5) -> Activity {
        Activity(source: .manual, sport: sport, start: start, duration: duration, distanceMeters: distanceMeters, perceivedExertion: perceivedExertion)
    }

    @Test("bySport groups totals correctly across two sports")
    func bySportGrouping() {
        let day = Date(timeIntervalSince1970: 0)
        let activities = [
            activity(sport: .running, start: day, distanceMeters: 5000, duration: 1800),
            activity(sport: .running, start: day.addingTimeInterval(3600), distanceMeters: 3000, duration: 1200),
            activity(sport: .cycling, start: day.addingTimeInterval(7200), distanceMeters: 20000, duration: 3600),
        ]

        let stats = calculator.periodStats(
            activities: activities,
            plans: [],
            workouts: [],
            athlete: athlete,
            range: day...day,
            asOf: day,
            previous: nil
        )

        #expect(stats.bySport[.running]?.activityCount == 2)
        #expect(stats.bySport[.running]?.distanceMeters == 8000)
        #expect(stats.bySport[.cycling]?.activityCount == 1)
        #expect(stats.bySport[.cycling]?.distanceMeters == 20000)
        #expect(stats.activityCount == 3)
        #expect(stats.totalDistanceMeters == 28000)
    }

    @Test("longest activity is tracked across sports")
    func longestActivityAcrossSports() {
        let day = Date(timeIntervalSince1970: 0)
        let activities = [
            activity(sport: .running, start: day, distanceMeters: 5000, duration: 1800),
            activity(sport: .cycling, start: day.addingTimeInterval(3600), distanceMeters: 40000, duration: 7200),
        ]

        let stats = calculator.periodStats(activities: activities, plans: [], workouts: [], athlete: athlete, range: day...day, asOf: day, previous: nil)

        #expect(stats.longestActivityTime == 7200)
        #expect(stats.longestActivityDistanceMeters == 40000)
    }

    @Test("an athlete on .lactateThreshold with no LTHR set reports empty time in zone, not a crash")
    func missingLactateThresholdReportsEmptyTimeInZone() {
        let athlete = AthleteProfile.fixture(lactateThresholdHeartRateBPM: nil, zoneMethod: .lactateThreshold)
        let samples = [
            HeartRateSample(time: Date(timeIntervalSince1970: 0), bpm: 140),
            HeartRateSample(time: Date(timeIntervalSince1970: 60), bpm: 150),
        ]
        let day = Date(timeIntervalSince1970: 0)
        let activity = Activity(source: .manual, sport: .running, start: day, duration: 60, heartRate: samples)

        let stats = calculator.periodStats(activities: [activity], plans: [], workouts: [], athlete: athlete, range: day...day, asOf: day, previous: nil)

        #expect(stats.timeInZone.total == 0)
        // The activity itself still contributes to the period's other totals.
        #expect(stats.activityCount == 1)
    }

    @Test("a custom gapThresholdSeconds applies to both load and time in zone")
    func gapThresholdSharedBetweenLoadAndTimeInZone() {
        // A 90-second gap: excluded from both load and time in zone at the default 60s threshold,
        // included in both at a custom 120s threshold — proving the two never disagree.
        let samples = [
            HeartRateSample(time: Date(timeIntervalSince1970: 0), bpm: 130),
            HeartRateSample(time: Date(timeIntervalSince1970: 90), bpm: 150),
        ]
        let day = Date(timeIntervalSince1970: 0)
        let activity = Activity(source: .manual, sport: .running, start: day, duration: 90, heartRate: samples)

        let strict = StatisticsCalculator(gapThresholdSeconds: 60).summary(for: activity, athlete: athlete)
        let lenient = StatisticsCalculator(gapThresholdSeconds: 120).summary(for: activity, athlete: athlete)

        #expect(strict.load.value == 0)
        #expect(strict.timeInZone.total == 0)
        #expect(lenient.load.value > 0)
        #expect(lenient.timeInZone.total == 90)
    }

    @Test("an actual activity on today wins over a plan on the same day, rather than summing both")
    func actualWinsOverPlanOnSameDay() {
        let day = Date(timeIntervalSince1970: 0)
        let realActivity = activity(sport: .running, start: day, distanceMeters: 5000, duration: 1800)
        let workout = StructuredWorkout(
            name: "Easy run",
            sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(1800), target: .heartRateZone(2))])]
        )
        let planSameDay = PlannedActivity(workoutID: workout.id, date: day)

        let stats = calculator.periodStats(
            activities: [realActivity],
            plans: [planSameDay],
            workouts: [workout],
            athlete: athlete,
            range: day...day,
            asOf: day,
            previous: nil
        )

        // Mirrors DailyLoadSeries's merge rule: only the actual activity should count on `today`
        // when one exists, not both — a double-count here would silently disagree with the
        // fitness series about the same day's totals.
        #expect(stats.activityCount == 1)
        #expect(stats.totalDistanceMeters == 5000)
        #expect(stats.totalTime == 1800)
    }

    @Test("delta is nil for the first call with no previous period")
    func deltaNilWithNoPrevious() {
        let day = Date(timeIntervalSince1970: 0)
        let stats = calculator.periodStats(activities: [], plans: [], workouts: [], athlete: athlete, range: day...day, asOf: day, previous: nil)

        #expect(stats.delta == nil)
    }
}
