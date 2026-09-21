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
        let distanceID = UUID(), timedID = UUID()
        let distanceWorkout = StructuredWorkout(
            id: distanceID, name: "D", sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .distance(10000))])]
        )
        let timedWorkout = workout(id: timedID, sport: .running, minutes: 47.5)
        // 9.8 km in 50 min: 2% off the planned distance, 5% off the timed plan's duration. The 10 km
        // plan's *estimated* duration (~43 min at the fixture's pace) is 14% off; if that estimate
        // were averaged in, the 10 km plan (7.8%) would lose to the timed plan (5%).
        let activity = Activity(source: .manual, sport: .running, start: day(0), duration: 3000, distanceMeters: 9800)
        let plans = [PlannedActivity(workoutID: timedID, date: day(0)), PlannedActivity(workoutID: distanceID, date: day(0))]

        let result = reconciler.reconcile(
            activities: [activity], plans: plans, workouts: [timedWorkout, distanceWorkout], athlete: athlete
        )

        #expect(result.activities[0].linkedPlanID == plans[1].id)
    }

    @Test("a workout mixing time and distance goals sets neither total and falls back to the estimate")
    func mixedGoalsFallBackToEstimate() {
        func mixed(id: UUID, meters: Double) -> StructuredWorkout {
            StructuredWorkout(id: id, name: "M", sport: .running, blocks: [WorkoutBlock(steps: [
                WorkoutStep(kind: .warmup, goal: .time(600)),
                WorkoutStep(kind: .work, goal: .distance(meters)),
            ])])
        }
        let shortID = UUID(), longID = UUID()
        let short = mixed(id: shortID, meters: 5000), long = mixed(id: longID, meters: 10000)
        #expect(reconciler.plannedDuration(of: short) == nil)
        #expect(reconciler.plannedDistance(of: short) == nil)

        let plans = [PlannedActivity(workoutID: shortID, date: day(0)), PlannedActivity(workoutID: longID, date: day(0))]
        // ~53 min: much nearer the long workout's estimate (~10 + 43 min) than the short one's (~10 + 22).
        let activity = Activity(source: .manual, sport: .running, start: day(0), duration: 53 * 60)

        let result = reconciler.reconcile(activities: [activity], plans: plans, workouts: [short, long], athlete: athlete)

        #expect(result.activities[0].linkedPlanID == plans[1].id)
    }

    @Test("day matching uses the athlete's time zone, not UTC")
    func timeZoneBoundary() throws {
        let auckland = try #require(TimeZone(identifier: "Pacific/Auckland"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = auckland
        let morning = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 8)))
        let lateEvening = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 23, minute: 30)))
        let nextMorning = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 11, hour: 1)))
        // Same Auckland day as the plan, though not the same UTC day (Auckland is UTC+13 in March).
        #expect(Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: lateEvening).day == 10)
        let workoutID = UUID()
        let workouts = [workout(id: workoutID, sport: .running, minutes: 30)]
        let plan = PlannedActivity(workoutID: workoutID, date: morning)
        let sameDay = Activity(source: .manual, sport: .running, start: lateEvening, duration: 1800)
        let otherDay = Activity(source: .manual, sport: .running, start: nextMorning, duration: 1800)
        let nzAthlete = AthleteProfile.fixture(timeZoneIdentifier: "Pacific/Auckland")

        let linked = reconciler.reconcile(activities: [sameDay], plans: [plan], workouts: workouts, athlete: nzAthlete)
        let notLinked = reconciler.reconcile(activities: [otherDay], plans: [plan], workouts: workouts, athlete: nzAthlete)

        #expect(linked.activities[0].linkedPlanID == plan.id)
        #expect(notLinked.activities[0].linkedPlanID == nil)
    }

    @Test("an outdoor run matches a plain running plan (same sport family)")
    func sportFamilyMatches() {
        let workoutID = UUID()
        let workouts = [workout(id: workoutID, sport: .running, minutes: 30)]
        let plan = PlannedActivity(workoutID: workoutID, date: day(0))
        let activity = Activity(source: .manual, sport: .outdoorRunning, start: day(0), duration: 1800)
        let cycling = Activity(source: .manual, sport: .cycling, start: day(0), duration: 1800)

        let result = reconciler.reconcile(activities: [activity, cycling], plans: [plan], workouts: workouts, athlete: athlete)

        #expect(result.activities[0].linkedPlanID == plan.id)
        #expect(result.activities[1].linkedPlanID == nil)
    }

    @Test("the outcome doesn't depend on the order activities are passed in")
    func orderIndependent() {
        let aID = UUID(), bID = UUID()
        let workouts = [workout(id: aID, sport: .running, minutes: 30), workout(id: bID, sport: .running, minutes: 40)]
        let plans = [PlannedActivity(workoutID: aID, date: day(0)), PlannedActivity(workoutID: bID, date: day(0))]
        // 36 min is slightly closer to the 40-min plan than the 30-min one, but the 31-min activity
        // fits the 30-min plan far better and should get it; the 36-min one then takes the 40-min plan.
        let near30 = Activity(source: .manual, sport: .running, start: day(0), duration: 31 * 60)
        let near40 = Activity(source: .manual, sport: .running, start: day(0), duration: 36 * 60)

        for order in [[near30, near40], [near40, near30]] {
            let result = reconciler.reconcile(activities: order, plans: plans, workouts: workouts, athlete: athlete)
            let linked = Dictionary(uniqueKeysWithValues: result.activities.map { ($0.id, $0.linkedPlanID) })
            #expect(linked[near30.id] == plans[0].id)
            #expect(linked[near40.id] == plans[1].id)
        }
    }
}
