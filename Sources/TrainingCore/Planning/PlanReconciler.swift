import Foundation

/// Links a completed ``Activity`` to a ``PlannedActivity`` on the same calendar day with the
/// same sport, so the fitness series can prefer "today's actual" over "today's estimate" per
/// §3.1's merge rule.
///
/// In MVP 1 this only affects that merge rule; in MVP 3 the `(expected, actual)` pairs it
/// produces become the training data for calibration.
public struct PlanReconciler: Sendable {
    /// Used only to tie-break candidate matches on duration; unlike ``TRIMPPlanEstimator`` this
    /// doesn't need to compute intensity, only elapsed time. Shared with `TRIMPPlanEstimator` so
    /// the two never silently disagree about how long a given workout is assumed to take.
    public var durationEstimator: WorkoutDurationEstimator

    public init(durationEstimator: WorkoutDurationEstimator = WorkoutDurationEstimator()) {
        self.durationEstimator = durationEstimator
    }

    /// Matches unlinked activities to unmatched plans on the same day and sport, tie-breaking on
    /// whichever candidate's planned duration is closest to the activity's actual duration.
    /// Returns updated copies with `Activity.linkedPlanID` and `PlannedActivity.completedActivityID`
    /// set; activities/plans that already carry a link, or find no match, are returned unchanged.
    public func reconcile(
        activities: [Activity],
        plans: [PlannedActivity],
        workouts: [StructuredWorkout],
        athlete: AthleteProfile
    ) -> (activities: [Activity], plans: [PlannedActivity]) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = athlete.timeZone

        let sportByWorkoutID = Dictionary(uniqueKeysWithValues: workouts.map { ($0.id, $0.sport) })
        var durationByWorkoutID: [UUID: TimeInterval] = [:]
        for workout in workouts {
            durationByWorkoutID[workout.id] = durationEstimator.duration(for: workout, athlete: athlete)
        }

        var activities = activities
        var plans = plans
        var claimedPlanIndices = Set<Int>()

        for activityIndex in activities.indices {
            guard activities[activityIndex].linkedPlanID == nil else { continue }
            let activity = activities[activityIndex]
            let activityDay = calendar.startOfDay(for: activity.start)

            var bestPlanIndex: Int?
            var bestDurationDelta = Double.infinity
            for planIndex in plans.indices {
                guard !claimedPlanIndices.contains(planIndex) else { continue }
                let plan = plans[planIndex]
                guard plan.completedActivityID == nil else { continue }
                guard calendar.isDate(plan.date, inSameDayAs: activityDay) else { continue }
                guard sportByWorkoutID[plan.workoutID] == activity.sport else { continue }

                let plannedDuration = durationByWorkoutID[plan.workoutID] ?? 0
                let delta = abs(plannedDuration - activity.duration)
                if delta < bestDurationDelta {
                    bestDurationDelta = delta
                    bestPlanIndex = planIndex
                }
            }

            if let bestPlanIndex {
                claimedPlanIndices.insert(bestPlanIndex)
                activities[activityIndex].linkedPlanID = plans[bestPlanIndex].id
                plans[bestPlanIndex].completedActivityID = activity.id
            }
        }

        return (activities, plans)
    }
}
