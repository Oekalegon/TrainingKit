import Foundation

/// Intensity classification of the model's activities and plans.
///
/// These read the loaded ``activities``, ``plans`` and ``workouts`` and are computed on demand,
/// not cached: classifying a performed activity walks its heart-rate samples, so compute once per
/// load (for example in a view model) rather than in a view body that re-evaluates often. They run
/// on the main actor like the rest of the model; the classifiers themselves
/// (``PerformedIntensityClassifier``, ``PlanGuidedIntensityClassifier``,
/// ``PlannedIntensityClassifier``) are `Sendable` values, so an app that classifies many activities
/// can run them off the main actor with the model's ``athlete`` and ``intensityParameters``.
///
/// The result depends on the plan an activity is linked to, so it isn't part of ``ActivitySummary``,
/// which is built from an activity alone.
extension TrainingModel {
    /// The intensity of a completed activity, or `nil` when there is nothing to go on.
    ///
    /// An activity linked to a plan whose workout is loaded is classified against that plan, with
    /// its heart rate checking whether the planned hard and tempo steps were performed
    /// (``PlanGuidedIntensityClassifier``). Any other activity is classified from its heart rate alone
    /// (``PerformedIntensityClassifier``), falling back to its perceived exertion.
    ///
    /// - Parameter activity: The activity to classify; it needn't be in ``activities``, but its
    ///   linked plan and that plan's workout are looked up in ``plans`` and ``workouts``.
    public func intensity(of activity: Activity) -> IntensityAssessment? {
        if let planID = activity.linkedPlanID,
           let plan = plans.first(where: { $0.id == planID }),
           let workout = workouts.first(where: { $0.id == plan.workoutID }) {
            return PlanGuidedIntensityClassifier(parameters: intensityParameters)
                .assess(activity, workout: workout, athlete: athlete)
        }
        return PerformedIntensityClassifier(parameters: intensityParameters).assess(activity, athlete: athlete)
    }

    /// The intended intensity of a planned activity, from its workout's steps, or `nil` when the
    /// workout isn't in ``workouts``.
    ///
    /// Independent of whether the plan has been completed; see ``intensity(of:)-(Activity)`` for what
    /// was actually performed.
    public func intensity(of plan: PlannedActivity) -> IntensityAssessment? {
        guard let workout = workouts.first(where: { $0.id == plan.workoutID }) else { return nil }
        return PlannedIntensityClassifier(parameters: intensityParameters).assess(workout, athlete: athlete)
    }
}
