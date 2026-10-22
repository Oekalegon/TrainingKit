import Foundation

/// Why ``TrainingModel/commit(_:named:activate:acceptingRisks:asOf:)`` refused a proposal (MVP5-121).
public enum PlanProposalError: Error, Sendable, Hashable {
    /// The proposal has these ``Severity/risk`` findings and was to be activated without
    /// `acceptingRisks`. Saving it as a draft is always allowed.
    case hasRisks([PlanFinding])
    /// Planned workouts refer to workouts that are neither in the proposal nor in the workout library.
    case missingWorkouts([UUID])
}
