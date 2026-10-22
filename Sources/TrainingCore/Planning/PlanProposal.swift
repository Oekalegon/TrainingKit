import Foundation

/// A plan the generator proposes, with everything the athlete needs to judge it: the findings of
/// every severity, what was given up, and how the adjust loop got here (MVP5-120).
///
/// Built by ``PlanAdjuster``. It inherits the NaN caveat of ``PlanCandidate/metrics``: encode it with a
/// non-conforming-float strategy, and compare its parts rather than whole proposals. It is not stored; the app previews it (MVP5-121) and, on commit, writes
/// ``draftPlan(named:id:)`` with the cycles and workouts of ``stamped(with:)``.
public struct PlanProposal: Sendable, Codable, Hashable {
    /// Why the adjust loop stopped.
    public enum Outcome: String, Sendable, Codable, Hashable {
        /// The plan has no ``Severity/risk`` finding.
        case acceptable
        /// Risks remain and no adjustment is left that was not tried, or could answer them.
        case noAdjustmentLeft
        /// Risks remain and ``PlanAdjuster/maxIterations`` adjustments were tried.
        case iterationLimit
    }

    /// The plan as built with ``levers``.
    public var candidate: PlanCandidate
    /// The guardrail observations on `candidate`, of every severity.
    public var evaluation: PlanEvaluation
    /// What the plan gave up: the provider's compromises, then the adjustments the loop kept.
    public var compromises: [PlanCompromise]
    /// The levers `candidate` was built with.
    public var levers: PlanLevers
    /// Every adjustment the loop tried, in order, kept or not.
    public var history: [PlanIteration]
    /// Why the loop stopped.
    public var outcome: Outcome
    /// The current day the proposal was made on, used as the draft plan's creation date.
    public var today: Date
    /// The race the plan builds towards, if any.
    public var targetRaceID: UUID?

    /// Creates a proposal.
    ///
    /// - Parameters:
    ///   - candidate: The plan.
    ///   - evaluation: The guardrail observations on it.
    ///   - compromises: What the plan gave up.
    ///   - levers: The levers it was built with.
    ///   - history: The adjustments tried; defaults to none.
    ///   - outcome: Why the loop stopped.
    ///   - today: The current day.
    ///   - targetRaceID: The race the plan builds towards; defaults to `nil`.
    public init(
        candidate: PlanCandidate,
        evaluation: PlanEvaluation,
        compromises: [PlanCompromise],
        levers: PlanLevers,
        history: [PlanIteration] = [],
        outcome: Outcome,
        today: Date,
        targetRaceID: UUID? = nil
    ) {
        self.candidate = candidate
        self.evaluation = evaluation
        self.compromises = compromises
        self.levers = levers
        self.history = history
        self.outcome = outcome
        self.today = today
        self.targetRaceID = targetRaceID
    }

    /// `false` when any finding is a ``Severity/risk``; warnings never make a proposal unacceptable.
    public var isAcceptable: Bool { evaluation.isAcceptable }

    /// The ``Severity/risk`` findings, in chronological order.
    public var risks: [PlanFinding] { evaluation.findings.filter { $0.severity == .risk } }

    /// The ``Severity/warning`` findings (race-day TSB, a high TSB, a missed intensity share), in
    /// chronological order, for the app to show next to the plan. They do not block it.
    public var warnings: [PlanFinding] { evaluation.findings.filter { $0.severity == .warning } }

    /// A draft plan for this proposal, created on ``today``.
    ///
    /// - Parameters:
    ///   - name: The display name.
    ///   - id: The plan's identifier; defaults to a new random `UUID`.
    public func draftPlan(named name: String, id: UUID = UUID()) -> TrainingPlan {
        TrainingPlan(
            id: id,
            name: name,
            status: .draft,
            macroCycleID: candidate.cycles.first { $0.level == .macro }?.id,
            targetRaceID: targetRaceID,
            createdDate: today
        )
    }

    /// The cycles and planned workouts of the proposal with their `planID` set to `plan`, ready to
    /// be stored with it.
    ///
    /// - Parameter plan: The plan they join, normally from ``draftPlan(named:id:)``.
    public func stamped(with plan: TrainingPlan) -> (cycles: [TrainingCycle], plannedActivities: [PlannedActivity]) {
        let cycles = candidate.cycles.map { cycle -> TrainingCycle in
            var cycle = cycle
            cycle.planID = plan.id
            return cycle
        }
        let activities = candidate.plannedActivities.map { activity -> PlannedActivity in
            var activity = activity
            activity.planID = plan.id
            return activity
        }
        return (cycles, activities)
    }
}
