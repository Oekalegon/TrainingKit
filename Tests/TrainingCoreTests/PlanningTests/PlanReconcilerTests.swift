import Foundation
import Testing
@testable import TrainingCore

@Suite("PlanReconciler")
struct PlanReconcilerTests {
    let athlete = AthleteProfile.fixture()
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

    @Test("a near-tie is linked to the closest plan but flagged as ambiguous")
    func nearTieFlagged() {
        let aID = UUID(), bID = UUID()
        let workouts = [
            workout(id: aID, sport: .running, minutes: 30),
            workout(id: bID, sport: .running, minutes: 32),
        ]
        let planA = PlannedActivity(workoutID: aID, date: day(0))
        let planB = PlannedActivity(workoutID: bID, date: day(0))
        let activity = Activity(source: .manual, sport: .running, start: day(0), duration: 31 * 60 + 30)

        let result = reconciler.reconcile(activities: [activity], plans: [planA, planB], workouts: workouts, athlete: athlete)

        #expect(result.activities[0].linkedPlanID == planB.id)
        #expect(result.ambiguities == [
            PlanMatchAmbiguity(activityID: activity.id, linkedPlanID: planB.id, alternativePlanIDs: [planA.id])
        ])
    }

    @Test("a clear winner is not flagged")
    func clearWinnerNotFlagged() {
        let shortID = UUID(), longID = UUID()
        let workouts = [
            workout(id: shortID, sport: .running, minutes: 20),
            workout(id: longID, sport: .running, minutes: 50),
        ]
        let plans = [PlannedActivity(workoutID: shortID, date: day(0)), PlannedActivity(workoutID: longID, date: day(0))]
        let activity = Activity(source: .manual, sport: .running, start: day(0), duration: 48 * 60)

        let result = reconciler.reconcile(activities: [activity], plans: plans, workouts: workouts, athlete: athlete)

        #expect(result.ambiguities.isEmpty)
    }

    @Test("distance separates plans with the same duration")
    func distanceBreaksDurationTie() {
        let shortID = UUID(), longID = UUID()
        func distanceWorkout(id: UUID, meters: Double) -> StructuredWorkout {
            StructuredWorkout(id: id, name: "D", sport: .running, blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .distance(meters))])])
        }
        let workouts = [distanceWorkout(id: shortID, meters: 5000), distanceWorkout(id: longID, meters: 10000)]
        let plans = [PlannedActivity(workoutID: shortID, date: day(0)), PlannedActivity(workoutID: longID, date: day(0))]
        let activity = Activity(source: .manual, sport: .running, start: day(0), duration: 3000, distanceMeters: 9800)

        let result = reconciler.reconcile(activities: [activity], plans: plans, workouts: workouts, athlete: athlete)

        #expect(result.activities[0].linkedPlanID == plans[1].id)
        #expect(result.ambiguities.isEmpty)
    }

    @Test("a distance plan is judged on its distance, not on a duration estimated from it")
    func estimatedDurationIgnoredForDistancePlan() {
        let runID = UUID(), timedID = UUID()
        let distanceWorkout = StructuredWorkout(
            id: runID, name: "D", sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .distance(10000))])]
        )
        let timedWorkout = workout(id: timedID, sport: .running, minutes: 40)
        // A slow 10 km: nowhere near the pace model's duration for it, but exactly the planned distance.
        let activity = Activity(source: .manual, sport: .running, start: day(0), duration: 40 * 60 + 30, distanceMeters: 10000)
        let plans = [PlannedActivity(workoutID: timedID, date: day(0)), PlannedActivity(workoutID: runID, date: day(0))]

        let result = reconciler.reconcile(
            activities: [activity], plans: plans, workouts: [timedWorkout, distanceWorkout], athlete: athlete
        )

        // Both match exactly on what they set (40 min vs 10 km) — an exact tie the earlier plan wins,
        // and it is flagged rather than silently resolved.
        #expect(result.ambiguities.first?.alternativePlanIDs.count == 1)
    }
}
