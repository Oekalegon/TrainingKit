import Foundation

/// A ``PlannedLoadEstimator`` that refines another estimator's figure with what the athlete's
/// completed, plan-linked activities actually scored.
///
/// A planned workout's own estimate is only as good as its intensity targets. Once the athlete has
/// done a workout, the load of the activity linked to its plan is a better guide, so this wraps a
/// `base` estimator and scales its figure by how the base has been off before.
///
/// **Scaling.** Each ``Reference`` is a workout that was done and the load it actually produced. Its
/// *correction* is `actual / base estimate of that workout`. The estimate for a workout is the base's
/// estimate of it multiplied by the **recency-weighted median** correction of the references that
/// match it: a reference's weight halves for every ``halfLife`` it is older than the most recent
/// one, so the latest runs count most while older ones still steady the figure. Because
/// each correction compares like with like, differences in a template's parameters and in the zone
/// a step targets are already accounted for: the base estimator weighs every step by its duration
/// and its zone's TRIMP weight, so a 60-minute tempo run is refined from a past 40-minute one
/// through the ratio of the two base estimates, not by the raw TRIMP of the 40 minutes. With the
/// same parameters and dates the result is simply the median actual TRIMP.
///
/// **Matching.** A reference matches a workout that is the same library workout, or was made from
/// the same ``WorkoutTemplate`` (``StructuredWorkout/templateID``) with other parameter values.
///
/// **Comparable runs only.** A reference that records the activity's duration is skipped when that
/// is not within ``durationTolerance`` of the workout's estimated duration: a 60-minute plan stopped
/// after 10 minutes says little about what the next full one will score.
///
/// **Not for residuals.** The estimate of a plan that already has its activity among the
/// references is about that activity's own load. Use ``excludingReferences(onOrAfter:)`` to
/// estimate a plan as it was before it was done, so expected-versus-actual comparisons stay honest.
///
/// A workout with no match, or whose base estimate is zero (no heart-rate zones on record), keeps
/// the base's result. Otherwise the result keeps `.estimatedFromPlan` but is more confident the more
/// references back it (see ``confidence(base:references:)``). A per-plan
/// ``PlannedActivity/expectedLoadOverride`` still wins over this, as over any estimator.
public struct LinkedActivityRefinedEstimator: PlannedLoadEstimator {
    /// A workout the athlete did, with the load of the activity linked to it.
    public struct Reference: Sendable, Hashable {
        /// The workout the linked plan scheduled.
        public var workout: StructuredWorkout
        /// The linked activity's measured load, in TRIMP; positive.
        public var actualLoad: Double
        /// When the activity was done; the newer, the more it weighs. Only differences between
        /// references matter, not the distance to now.
        public var date: Date
        /// How long the activity lasted, or `nil` to skip the comparable-duration check.
        public var actualDuration: TimeInterval?

        /// Creates a reference.
        ///
        /// - Parameters:
        ///   - workout: The workout the linked plan scheduled.
        ///   - actualLoad: The linked activity's measured load, in TRIMP.
        ///   - date: When the activity was done; defaults to `.distantPast`, which weighs the same
        ///     as any other reference with no date.
        ///   - actualDuration: How long the activity lasted, in seconds; defaults to `nil`.
        public init(workout: StructuredWorkout, actualLoad: Double, date: Date = .distantPast, actualDuration: TimeInterval? = nil) {
            self.workout = workout
            self.actualLoad = actualLoad
            self.date = date
            self.actualDuration = actualDuration
        }
    }

    /// The estimator whose figure is refined, and which scores each reference's own workout.
    public var base: any PlannedLoadEstimator
    /// The completed workouts to refine from.
    public var references: [Reference]
    /// How much older than the most recent reference one must be to weigh half as much; defaults
    /// to 60 days, as ``HistoricalPaceEstimator``'s recency weighting.
    public var halfLife: TimeInterval
    /// Turns a workout into its estimated duration, for the comparable-duration check.
    public var durationEstimator: WorkoutDurationEstimator
    /// The accepted ratio of an activity's duration to its workout's estimated duration; a
    /// reference outside it is skipped. Defaults to `0.75...1.33`.
    public var durationTolerance: ClosedRange<Double>

    /// Creates a refining estimator.
    ///
    /// - Parameters:
    ///   - base: The estimator whose figure is refined; defaults to ``TRIMPPlanEstimator``.
    ///   - references: The completed workouts and their actual loads. Ones with a non-positive
    ///     load are ignored.
    ///   - halfLife: The age, relative to the most recent reference, at which a reference's weight
    ///     halves; defaults to 60 days.
    ///   - durationEstimator: Estimates a workout's duration; defaults to a plain one.
    ///   - durationTolerance: The accepted activity-to-estimated duration ratio; defaults to `0.75...1.33`.
    public init(
        base: any PlannedLoadEstimator = TRIMPPlanEstimator(),
        references: [Reference],
        halfLife: TimeInterval = 60 * 86_400,
        durationEstimator: WorkoutDurationEstimator = WorkoutDurationEstimator(),
        durationTolerance: ClosedRange<Double> = 0.75...1.33
    ) {
        self.base = base
        self.halfLife = halfLife
        self.durationEstimator = durationEstimator
        self.durationTolerance = durationTolerance
        self.references = references.filter { $0.actualLoad > 0 }
    }

    /// Creates a refining estimator from the plans the athlete has completed.
    ///
    /// - Parameters:
    ///   - base: The estimator whose figure is refined.
    ///   - plans: Every plan to consider; only those with a ``PlannedActivity/completedActivityID``
    ///     whose activity is in `activities` and whose workout is in `workouts` count.
    ///   - workouts: The library workouts `plans` reference.
    ///   - activities: The activities the plans were completed by.
    ///   - calculators: Tried in order per activity; the first to succeed gives its actual load.
    ///   - athlete: Passed through to `calculators`.
    ///   - halfLife: See ``halfLife``.
    ///   - durationEstimator: See ``durationEstimator``.
    ///   - durationTolerance: See ``durationTolerance``.
    public init(
        base: any PlannedLoadEstimator = TRIMPPlanEstimator(),
        plans: [PlannedActivity],
        workouts: [StructuredWorkout],
        activities: [UUID: Activity],
        calculators: [any LoadCalculator],
        athlete: AthleteProfile,
        halfLife: TimeInterval = 60 * 86_400,
        durationEstimator: WorkoutDurationEstimator = WorkoutDurationEstimator(),
        durationTolerance: ClosedRange<Double> = 0.75...1.33
    ) {
        let workoutsByID = Dictionary(workouts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var references: [Reference] = []
        for plan in plans {
            guard let activityID = plan.completedActivityID, let activity = activities[activityID],
                  let workout = workoutsByID[plan.workoutID] else { continue }
            guard let load = calculators.lazy.compactMap({ try? $0.load(for: activity, athlete: athlete).value }).first
            else { continue }
            references.append(Reference(workout: workout, actualLoad: load, date: activity.start, actualDuration: activity.duration))
        }
        self.init(
            base: base, references: references, halfLife: halfLife,
            durationEstimator: durationEstimator, durationTolerance: durationTolerance
        )
    }

    /// The base estimate of `workout`, scaled by the recency-weighted median correction of its matching references.
    ///
    /// - Parameters:
    ///   - workout: The workout to estimate.
    ///   - athlete: Passed to the base estimator.
    /// - Returns: A ``TrainingLoad`` with `method: .estimatedFromPlan`; the base's own result when
    ///   nothing matches `workout` or the base can't score it.
    public func estimatedLoad(for workout: StructuredWorkout, athlete: AthleteProfile) -> TrainingLoad {
        let estimate = base.estimatedLoad(for: workout, athlete: athlete)
        guard estimate.value > 0 else { return estimate }
        let matching = references.filter { Self.matches($0.workout, workout) }
        let newest = matching.map(\.date).max() ?? .distantPast
        var corrections: [(value: Double, weight: Double)] = []
        for reference in matching {
            let referenceEstimate = base.estimatedLoad(for: reference.workout, athlete: athlete).value
            guard referenceEstimate > 0 else { continue }
            if let actual = reference.actualDuration {
                let planned = durationEstimator.duration(for: reference.workout, athlete: athlete)
                guard planned > 0, durationTolerance.contains(actual / planned) else { continue }
            }
            let age = newest.timeIntervalSince(reference.date)
            let weight = halfLife > 0 ? pow(0.5, age / halfLife) : (age == 0 ? 1 : 0)
            corrections.append((reference.actualLoad / referenceEstimate, weight))
        }
        guard let correction = Self.weightedMedian(corrections) else { return estimate }
        return TrainingLoad(
            value: estimate.value * correction,
            method: .estimatedFromPlan,
            confidence: Self.confidence(base: estimate.confidence, references: corrections.count)
        )
    }

    /// This estimator without the references dated on or after `cutoff`, so a plan estimated with
    /// its own date as the cutoff isn't informed by its own activity.
    ///
    /// - Parameter cutoff: References from this instant on are dropped.
    public func excludingReferences(onOrAfter cutoff: Date) -> LinkedActivityRefinedEstimator {
        var copy = self
        copy.references = references.filter { $0.date < cutoff }
        return copy
    }

    /// The weighted median of `samples`: the value where the cumulative weight reaches half the
    /// total, averaged with the next value when it lands exactly on half (so equal weights give the
    /// ordinary median). `nil` when empty.
    static func weightedMedian(_ samples: [(value: Double, weight: Double)]) -> Double? {
        let sorted = samples.filter { $0.weight > 0 }.sorted { $0.value < $1.value }
        guard !sorted.isEmpty else { return nil }
        let half = sorted.reduce(0) { $0 + $1.weight } / 2
        var cumulative = 0.0
        for (index, sample) in sorted.enumerated() {
            cumulative += sample.weight
            if abs(cumulative - half) <= 1e-9 * half, index + 1 < sorted.count {
                return (sample.value + sorted[index + 1].value) / 2
            }
            if cumulative > half { return sample.value }
        }
        return sorted.last?.value
    }

    /// Whether `reference` was made from the same library workout or template as `workout`.
    private static func matches(_ reference: StructuredWorkout, _ workout: StructuredWorkout) -> Bool {
        if reference.id == workout.id { return true }
        guard let template = workout.templateID else { return false }
        return reference.templateID == template
    }

    /// The confidence after refining from `references` completed workouts: each one halves the
    /// distance between `base` and 1 (0.7 becomes 0.85 after one, 0.925 after two), capped at 0.95
    /// since it's still an estimate.
    ///
    /// - Parameters:
    ///   - base: The base estimator's confidence.
    ///   - references: How many matching references backed the result.
    public static func confidence(base: Double, references: Int) -> Double {
        let refined = 1 - (1 - base) * pow(0.5, Double(references))
        return max(base, min(refined, 0.95))
    }
}
