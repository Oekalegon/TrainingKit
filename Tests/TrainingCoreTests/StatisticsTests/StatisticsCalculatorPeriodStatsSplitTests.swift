import Foundation
import Testing
@testable import TrainingCore

@Suite("StatisticsCalculator.periodStatsSplit")
struct StatisticsCalculatorPeriodStatsSplitTests {
    let athlete = AthleteProfile.fixture()
    let calculator = StatisticsCalculator()

    private func activity(sport: Sport, start: Date, distanceMeters: Double, duration: TimeInterval, perceivedExertion: Int = 5) -> Activity {
        Activity(source: .manual, sport: sport, start: start, duration: duration, distanceMeters: distanceMeters, perceivedExertion: perceivedExertion)
    }

    private func workout(sport: Sport = .running) -> StructuredWorkout {
        StructuredWorkout(
            name: "Easy run", sport: sport,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(1800), target: .heartRateZone(2))])]
        )
    }

    @Test("a day with only a plan not yet performed reports it under planned, not actual")
    func plannedOnlyWhenNotYetPerformed() {
        let day = Date(timeIntervalSince1970: 0)
        let structuredWorkout = workout()
        let plan = PlannedActivity(workoutID: structuredWorkout.id, date: day)

        let split = calculator.periodStatsSplit(
            activities: [], plans: [plan], workouts: [structuredWorkout], athlete: athlete, range: day...day, asOf: day
        )

        #expect(split.planned[.running]?.activityCount == 1)
        #expect(split.actual[.running] == nil)
    }

    @Test("a day with both a plan and its completed activity reports both independently, unlike periodStats' either/or merge")
    func bothReportedIndependentlyWhenBothExist() {
        let day = Date(timeIntervalSince1970: 0)
        let structuredWorkout = workout()
        let plan = PlannedActivity(workoutID: structuredWorkout.id, date: day)
        // More distance than the plan's own workout projects, so actual/planned can be told apart.
        let realActivity = activity(sport: .running, start: day, distanceMeters: 8000, duration: 2400)

        let split = calculator.periodStatsSplit(
            activities: [realActivity], plans: [plan], workouts: [structuredWorkout], athlete: athlete, range: day...day, asOf: day
        )

        #expect(split.actual[.running]?.activityCount == 1)
        #expect(split.actual[.running]?.distanceMeters == 8000)
        #expect(split.planned[.running]?.activityCount == 1)
        // Unlike periodStats (which would drop the plan entirely once an activity exists that
        // day), the plan's own projected distance is still reported here.
        #expect(split.planned[.running]?.distanceMeters != 8000)
    }

    @Test("a completed activity with no matching plan reports only actual")
    func actualOnlyWithNoPlan() {
        let day = Date(timeIntervalSince1970: 0)
        let realActivity = activity(sport: .running, start: day, distanceMeters: 5000, duration: 1800)

        let split = calculator.periodStatsSplit(
            activities: [realActivity], plans: [], workouts: [], athlete: athlete, range: day...day, asOf: day
        )

        #expect(split.actual[.running]?.activityCount == 1)
        #expect(split.planned[.running] == nil)
    }

    @Test("a plan dated before today is excluded, unlike an on-or-after-today one")
    func excludesPastUnperformedPlans() {
        let today = Date(timeIntervalSince1970: 5 * 86400)
        let pastDay = Date(timeIntervalSince1970: 2 * 86400)
        let structuredWorkout = workout()
        let pastPlan = PlannedActivity(workoutID: structuredWorkout.id, date: pastDay)
        let futurePlan = PlannedActivity(workoutID: structuredWorkout.id, date: today.addingTimeInterval(86400))

        let split = calculator.periodStatsSplit(
            activities: [], plans: [pastPlan, futurePlan], workouts: [structuredWorkout], athlete: athlete,
            range: pastDay...today.addingTimeInterval(86400), asOf: today
        )

        #expect(split.planned[.running]?.activityCount == 1)
    }

    @Test("bySport groups both sides across two sports independently")
    func bySportGroupingBothSides() {
        let day = Date(timeIntervalSince1970: 0)
        let runningWorkout = workout(sport: .running)
        let cyclingWorkout = workout(sport: .cycling)
        let activities = [
            activity(sport: .running, start: day, distanceMeters: 5000, duration: 1800),
            activity(sport: .cycling, start: day, distanceMeters: 20000, duration: 3600),
        ]
        let plans = [
            PlannedActivity(workoutID: runningWorkout.id, date: day),
            PlannedActivity(workoutID: cyclingWorkout.id, date: day),
        ]

        let split = calculator.periodStatsSplit(
            activities: activities, plans: plans, workouts: [runningWorkout, cyclingWorkout], athlete: athlete,
            range: day...day, asOf: day
        )

        #expect(split.actual[.running]?.distanceMeters == 5000)
        #expect(split.actual[.cycling]?.distanceMeters == 20000)
        #expect(split.planned[.running] != nil)
        #expect(split.planned[.cycling] != nil)
    }
}
