/// The template counterpart of ``WorkoutStep``, e.g. "work at Zone 4 for a variable duration".
public struct TemplateStep: Sendable, Codable, Hashable {
    /// The role this step plays within its block.
    public var kind: StepKind
    /// What ends this step.
    public var goal: TemplateStepGoal
    /// The intensity this step targets, if any.
    public var target: IntensityTarget?

    /// Creates a template step.
    ///
    /// - Parameters:
    ///   - kind: The role this step plays within its block.
    ///   - goal: What ends this step.
    ///   - target: The intensity this step targets, if any.
    public init(kind: StepKind, goal: TemplateStepGoal, target: IntensityTarget? = nil) {
        self.kind = kind
        self.goal = goal
        self.target = target
    }
}
