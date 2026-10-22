import Foundation

/// Why ``TrainingModel/commit(_:named:activate:acceptingRisks:asOf:)`` refused a proposal (MVP5-121).
public enum PlanProposalError: Error, Sendable, Hashable {
    /// The proposal has these ``Severity/risk`` findings and was to be activated without
    /// `acceptingRisks`. Saving it as a draft is always allowed.
    case hasRisks([PlanFinding])
    /// Planned workouts refer to workouts that are neither in the proposal nor in the workout library.
    /// The ids are in the order of their `uuidString`.
    case missingWorkouts([UUID])
    /// The proposal holds workouts whose ids are already in the workout library with other content;
    /// saving them would overwrite those. The provider must give new workouts new ids.
    case workoutIDCollision([UUID])
    /// Planned workouts name cycles (``PlannedActivity/cycleID``) that are not among the proposal's
    /// cycles. The ids are those of the missing cycles, in the order of their `uuidString`.
    case danglingCycleReferences([UUID])
}
