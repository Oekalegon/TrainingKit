import Foundation
import Testing
@testable import TrainingCore

@Suite("DailyLoadSeries")
struct DailyLoadSeriesTests {
    let athlete = AthleteProfile(
        restingHeartRateBPM: 50,
        maxHeartRateBPM: 190,
        sex: .male,
        paceModel: PaceModel(thresholdPaceSecondsPerKilometer: 240),
        timeZone: TimeZone(identifier: "UTC")!
    )
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

        #expect(days.count == 1)
        #expect(days.first?.day == localDayStart)
    }
}
