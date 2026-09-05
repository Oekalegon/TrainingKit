import Foundation
import Testing
@testable import TrainingCore

@Suite("PlanReconciler")
struct PlanReconcilerTests {
    let athlete = AthleteProfile(
        restingHeartRateBPM: 50,
        maxHeartRateBPM: 190,
        sex: .male,
        paceModel: PaceModel(thresholdPaceSecondsPerKilometer: 240),
        timeZone: TimeZone(identifier: "UTC")!
    )
    let reconciler = PlanReconciler()

    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    private func workout(id: UUID, sport: Sport, minutes: Double) -> StructuredWorkout {
        StructuredWorkout(id: id, name: "W", sport: sport, blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(minutes * 60))])])
    }

    @Test("links a same-day, same-sport activity to its plan")
    func sameDaySameSportLink() {
        let workoutID = UUID()
        let workouts = [workout(id: workoutID, sport: .running, minutes: 30)]
        let plan = PlannedActivity(workoutID: workoutID, date: day(0))
        let activity = Activity(source: .manual, sport: .running, start: day(0), duration: 1800)

        let result = reconciler.reconcile(activities: [activity], plans: [plan], workouts: workouts, athlete: athlete)

        #expect(result.activities[0].linkedPlanID == plan.id)
        #expect(result.plans[0].completedActivityID == activity.id)
    }

    @Test("ties are broken on closest planned duration")
    func tieBreakOnDuration() {
        let shortWorkoutID = UUID()
        let longWorkoutID = UUID()
        let workouts = [
            workout(id: shortWorkoutID, sport: .running, minutes: 20),
            workout(id: longWorkoutID, sport: .running, minutes: 50),
        ]
        let shortPlan = PlannedActivity(workoutID: shortWorkoutID, date: day(0))
        let longPlan = PlannedActivity(workoutID: longWorkoutID, date: day(0))
        // Actual duration (45 min) is much closer to the 50-minute plan than the 20-minute one.
        let activity = Activity(source: .manual, sport: .running, start: day(0), duration: 45 * 60)

        let result = reconciler.reconcile(
            activities: [activity], plans: [shortPlan, longPlan], workouts: workouts, athlete: athlete
        )

        #expect(result.activities[0].linkedPlanID == longPlan.id)
    }

    @Test("plans and activities on different days are never linked")
    func noCrossDayLinks() {
        let workoutID = UUID()
        let workouts = [workout(id: workoutID, sport: .running, minutes: 30)]
        let plan = PlannedActivity(workoutID: workoutID, date: day(0))
        let activity = Activity(source: .manual, sport: .running, start: day(1), duration: 1800)

        let result = reconciler.reconcile(activities: [activity], plans: [plan], workouts: workouts, athlete: athlete)

        #expect(result.activities[0].linkedPlanID == nil)
        #expect(result.plans[0].completedActivityID == nil)
    }
}
