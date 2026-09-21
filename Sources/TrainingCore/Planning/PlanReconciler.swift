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

    /// How much better than the runner-up the winning plan's mismatch score must be for the match
    /// to count as clear, as a fraction (0.05 = five percentage points of relative duration/distance
    /// error). A runner-up within this margin is reported in ``PlanReconciliation/ambiguities`` so
    /// the athlete can confirm or correct the link.
    public var ambiguityTolerance: Double

    /// Creates a plan reconciler.
    ///
    /// - Parameters:
    ///   - durationEstimator: Used to tie-break candidate matches on duration.
    ///   - ambiguityTolerance: Relative score margin within which a runner-up plan makes a match
    ///     ambiguous; defaults to 0.05.
    public init(
        durationEstimator: WorkoutDurationEstimator = WorkoutDurationEstimator(),
        ambiguityTolerance: Double = 0.05
    ) {
        self.durationEstimator = durationEstimator
        self.ambiguityTolerance = ambiguityTolerance
    }

    /// Matches unlinked activities to unmatched plans on the same day and sport, picking whichever
    /// candidate's planned workout is most similar to what was actually recorded, judged on what the
    /// plan explicitly sets: the relative difference in total duration if every step has a time goal
    /// (see ``plannedDuration(of:)``), averaged with that in distance if every step has a distance
    /// goal and the activity recorded one (see ``plannedDistance(of:)``). Only a workout that sets
    /// neither falls back to ``durationEstimator``'s estimate.
    /// Returns updated copies with `Activity.linkedPlanID` and `PlannedActivity.completedActivityID`
    /// set; activities/plans that already carry a link, or find no match, are returned unchanged.
    ///
    /// A near-tie is still linked to the closest plan (the best guess) but is also reported in
    /// ``PlanReconciliation/ambiguities``, never silently resolved.
    public func reconcile(
        activities: [Activity],
        plans: [PlannedActivity],
        workouts: [StructuredWorkout],
        athlete: AthleteProfile
    ) -> PlanReconciliation {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = athlete.timeZone

        let sportByWorkoutID = Dictionary(uniqueKeysWithValues: workouts.map { ($0.id, $0.sport) })
        var durationByWorkoutID: [UUID: TimeInterval] = [:]
        for workout in workouts {
            durationByWorkoutID[workout.id] = durationEstimator.duration(for: workout, athlete: athlete)
        }

        let distanceByWorkoutID = workouts.reduce(into: [UUID: Double]()) { result, workout in
            if let meters = plannedDistance(of: workout) { result[workout.id] = meters }
        }

        let explicitDurationByWorkoutID = workouts.reduce(into: [UUID: TimeInterval]()) { result, workout in
            if let seconds = plannedDuration(of: workout) { result[workout.id] = seconds }
        }

        var activities = activities
        var plans = plans

        // Every viable (activity, plan) pair with its mismatch score. Plans are only ever candidates
        // for activities on their own day (and sport), so a link never crosses days.
        var candidatesByActivity: [Int: [(plan: Int, score: Double)]] = [:]
        for activityIndex in activities.indices {
            guard activities[activityIndex].linkedPlanID == nil else { continue }
            let activity = activities[activityIndex]
            let activityDay = calendar.startOfDay(for: activity.start)

            for planIndex in plans.indices {
                let plan = plans[planIndex]
                guard plan.completedActivityID == nil else { continue }
                guard calendar.isDate(plan.date, inSameDayAs: activityDay) else { continue }
                guard sportByWorkoutID[plan.workoutID]?.isSameFamily(as: activity.sport) == true else { continue }

                // Explicit targets only: a duration or distance the plan actually sets outranks one
                // merely estimated from the other. The estimate is a last resort, for workouts that
                // set neither (open or mixed-goal steps).
                var errors: [Double] = []
                if let plannedSeconds = explicitDurationByWorkoutID[plan.workoutID] {
                    errors.append(Self.relativeError(plannedSeconds, activity.duration))
                }
                if let plannedMeters = distanceByWorkoutID[plan.workoutID], let actualMeters = activity.distanceMeters {
                    errors.append(Self.relativeError(plannedMeters, actualMeters))
                }
                if errors.isEmpty {
                    errors.append(Self.relativeError(durationByWorkoutID[plan.workoutID] ?? 0, activity.duration))
                }
                candidatesByActivity[activityIndex, default: []].append((planIndex, errors.reduce(0, +) / Double(errors.count)))
            }
        }

        // Best pairs first across *all* activities, so the outcome doesn't depend on the order the
        // activities were passed in: a plan goes to whichever activity fits it best. Exact ties fall
        // back to array order (stable).
        let pairs = candidatesByActivity
            .flatMap { activityIndex, candidates in candidates.map { (activity: activityIndex, plan: $0.plan, score: $0.score) } }
            .sorted { ($0.score, $0.activity, $0.plan) < ($1.score, $1.activity, $1.plan) }
        var planByActivity: [Int: (plan: Int, score: Double)] = [:]
        var claimedPlanIndices = Set<Int>()
        for pair in pairs where planByActivity[pair.activity] == nil && !claimedPlanIndices.contains(pair.plan) {
            planByActivity[pair.activity] = (pair.plan, pair.score)
            claimedPlanIndices.insert(pair.plan)
        }

        var ambiguities: [PlanMatchAmbiguity] = []
        for activityIndex in planByActivity.keys.sorted() {
            guard let chosen = planByActivity[activityIndex] else { continue }
            let activityID = activities[activityIndex].id
            let chosenPlanID = plans[chosen.plan].id
            // Alternatives are plans no *other* activity took and that fit almost as well.
            let alternatives = (candidatesByActivity[activityIndex] ?? []).filter {
                $0.plan != chosen.plan && !claimedPlanIndices.contains($0.plan)
                    && abs($0.score - chosen.score) <= ambiguityTolerance
            }
            if !alternatives.isEmpty {
                ambiguities.append(PlanMatchAmbiguity(
                    activityID: activityID, linkedPlanID: chosenPlanID,
                    alternativePlanIDs: alternatives.map { plans[$0.plan].id }
                ))
            }
        }
        for (activityIndex, chosen) in planByActivity {
            activities[activityIndex].linkedPlanID = plans[chosen.plan].id
            plans[chosen.plan].completedActivityID = activities[activityIndex].id
        }

        return PlanReconciliation(activities: activities, plans: plans, ambiguities: ambiguities)
    }

    /// The workout's total duration if every step has a `.time` goal, else `nil` — a distance or open
    /// step only has an estimated duration, which doesn't count as something the plan sets. Respects
    /// each block's `repetitions`.
    public func plannedDuration(of workout: StructuredWorkout) -> TimeInterval? {
        var total: TimeInterval = 0
        for block in workout.blocks {
            var blockTotal: TimeInterval = 0
            for step in block.steps {
                guard case .time(let seconds) = step.goal else { return nil }
                blockTotal += seconds
            }
            total += blockTotal * Double(block.repetitions)
        }
        return total > 0 ? total : nil
    }

    /// The workout's total distance in meters, or `nil` unless every step has a `.distance` goal
    /// (a time or open step has no distance without assuming a pace, which would be wrong off the
    /// run). Respects each block's `repetitions`.
    public func plannedDistance(of workout: StructuredWorkout) -> Double? {
        var total = 0.0
        for block in workout.blocks {
            var blockTotal = 0.0
            for step in block.steps {
                guard case .distance(let meters) = step.goal else { return nil }
                blockTotal += meters
            }
            total += blockTotal * Double(block.repetitions)
        }
        return total > 0 ? total : nil
    }

    /// `|a - b| / max(a, b)`: 0 for equal values, approaching 1 as they diverge.
    private static func relativeError(_ a: Double, _ b: Double) -> Double {
        let larger = max(a, b)
        return larger > 0 ? abs(a - b) / larger : 0
    }
}
