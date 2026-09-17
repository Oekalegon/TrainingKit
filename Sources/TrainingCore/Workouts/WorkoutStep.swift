/// A single step within a ``WorkoutBlock``, e.g. "5 minutes warmup" or "400m at Zone 4".
public struct WorkoutStep: Sendable, Codable, Hashable {
    /// The role this step plays within its block.
    public var kind: StepKind
    /// What ends this step.
    public var goal: StepGoal
    /// The intensity this step targets, if any.
    public var target: IntensityTarget?

    /// Creates a workout step.
    ///
    /// - Parameters:
    ///   - kind: The role this step plays within its block.
    ///   - goal: What ends this step.
    ///   - target: The intensity this step targets, if any.
    public init(kind: StepKind, goal: StepGoal, target: IntensityTarget? = nil) {
        self.kind = kind
        self.goal = goal
        self.target = target
    }
}
