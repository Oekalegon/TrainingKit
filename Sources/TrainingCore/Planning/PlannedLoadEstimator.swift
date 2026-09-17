/// Estimates the training load a ``StructuredWorkout`` will produce, without any measured data.
///
/// This is the seam MVP 3 replaces with a calibrated estimator that scales by observed
/// planned-vs-actual residuals; callers should depend on the protocol, not `TRIMPPlanEstimator`.
public protocol PlannedLoadEstimator: Sendable {
    func estimatedLoad(for workout: StructuredWorkout, athlete: AthleteProfile) -> TrainingLoad
}
