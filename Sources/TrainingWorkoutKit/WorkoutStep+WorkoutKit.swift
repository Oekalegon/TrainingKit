import TrainingCore
// TrainingCore and WorkoutKit both export a type named `WorkoutStep`, and TrainingCore also
// exports a top-level enum literally named `TrainingCore`, which shadows the module-qualified
// spelling `TrainingCore.WorkoutStep`. This scoped import binds the bare name unambiguously to
// Core's type; WorkoutKit's is always referenced as `WorkoutKit.WorkoutStep` below.
import struct TrainingCore.WorkoutStep

#if canImport(WorkoutKit)
import WorkoutKit

extension WorkoutKit.WorkoutStep {
    /// Maps a Core `WorkoutStep`'s goal and target onto a WorkoutKit step. `kind` isn't carried
    /// here — WorkoutKit doesn't have a per-step role field, only the warmup/cooldown slots on
    /// `CustomWorkout` and `IntervalStep.Purpose`'s work/recovery, both handled by the caller.
    ///
    /// - Parameter coreStep: The Core step to map.
    public init(coreStep: WorkoutStep) {
        self.init(goal: WorkoutGoal(stepGoal: coreStep.goal), alert: coreStep.target?.workoutAlert)
    }
}

extension WorkoutStep {
    /// Maps a WorkoutKit step back onto a Core `WorkoutStep`, given the `kind` the caller has
    /// already determined (from the warmup/cooldown slot or an `IntervalStep.Purpose`).
    ///
    /// - Parameters:
    ///   - kind: The role this step plays, as already determined by the caller.
    ///   - workoutKitStep: The WorkoutKit step to map.
    /// - Throws: ``WorkoutKitMappingError/unsupportedGoal(_:)`` if `workoutKitStep.goal` has no
    ///   `StepGoal` equivalent. A non-representable `alert` is dropped silently (mapped to `nil`),
    ///   same as `IntensityTarget(workoutAlert:)` does for its unsupported cases.
    public init(kind: StepKind, workoutKitStep: WorkoutKit.WorkoutStep) throws(WorkoutKitMappingError) {
        self.init(
            kind: kind,
            goal: try StepGoal(workoutGoal: workoutKitStep.goal),
            target: workoutKitStep.alert.flatMap { IntensityTarget(workoutAlert: $0) }
        )
    }
}
#endif
