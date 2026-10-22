import Foundation

/// What the athlete sees before committing a ``PlanProposal`` (MVP5-121): the plan itself, how it
/// would be judged, what it gave up, and what it would replace.
///
/// Built by ``TrainingModel/preview(_:asOf:)``. Like ``PlanProposal`` it holds a series with `.nan` values, so
/// a preview is not equal to a copy of itself; compare its parts. The views below read the proposal; the only
/// information that comes from elsewhere is what the plan being replaced holds.
public struct PlanPreview: Sendable, Hashable {
    /// The proposal being previewed.
    public let proposal: PlanProposal
    /// The plan that is active now and stops feeding the series if the proposal is activated; `nil` if
    /// none is active (or there is no ``StoreSet/trainingPlanStore``).
    public let replacedPlan: TrainingPlan?
    /// The planned workouts of ``replacedPlan`` from today on that no activity has completed: the ones
    /// that stop counting on activation. Nothing is deleted. In date order.
    public let replacedActivities: [PlannedActivity]
    /// Whether ``replacedPlan`` has a completed workout. If so, activating the proposal cancels it
    /// (dated today) and keeps it as history; if not, it becomes a draft.
    public let replacedPlanIsFollowed: Bool

    /// Creates a preview.
    ///
    /// - Parameters:
    ///   - proposal: The proposal.
    ///   - replacedPlan: The active plan it would replace, if any.
    ///   - replacedActivities: Its upcoming, uncompleted planned workouts.
    ///   - replacedPlanIsFollowed: Whether it has a completed workout.
    public init(proposal: PlanProposal, replacedPlan: TrainingPlan?, replacedActivities: [PlannedActivity], replacedPlanIsFollowed: Bool) {
        self.proposal = proposal
        self.replacedPlan = replacedPlan
        self.replacedActivities = replacedActivities
        self.replacedPlanIsFollowed = replacedPlanIsFollowed
    }

    /// The layout: the proposal's macro, meso and micro cycles.
    public var cycles: [TrainingCycle] { proposal.candidate.cycles }
    /// The planned workouts, with their workouts in ``workouts``.
    public var plannedActivities: [PlannedActivity] { proposal.candidate.plannedActivities }
    /// The workouts the planned workouts refer to.
    public var workouts: [StructuredWorkout] { proposal.candidate.workouts }
    /// The projected form (CTL, ATL, TSB) with the proposal in it.
    public var projectedForm: [FitnessMetrics] { proposal.candidate.metrics }
    /// What the proposal gave up.
    public var compromises: [PlanCompromise] { proposal.compromises }
    /// The ``Severity/risk`` findings; the proposal can be saved as a draft but not activated without
    /// accepting them.
    public var risks: [PlanFinding] { proposal.risks }
    /// The ``Severity/warning`` findings; shown, never blocking.
    public var warnings: [PlanFinding] { proposal.warnings }
    /// The notice that the paradigm's numbers are not calibrated for the target race's distance, if any
    /// (MVP5-143); see ``PlanProposal/calibrationWarning``.
    public var calibrationWarning: CalibrationWarning? { proposal.calibrationWarning }
    /// Whether the proposal has no risk.
    public var isAcceptable: Bool { proposal.isAcceptable }
}
