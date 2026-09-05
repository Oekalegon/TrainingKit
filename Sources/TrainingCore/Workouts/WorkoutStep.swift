/// A single step within a ``WorkoutBlock``, e.g. "5 minutes warmup" or "400m at Zone 4".
public struct WorkoutStep: Sendable, Codable, Hashable {
    public var kind: StepKind
    public var goal: StepGoal
    public var target: IntensityTarget?

    public init(kind: StepKind, goal: StepGoal, target: IntensityTarget? = nil) {
        self.kind = kind
        self.goal = goal
        self.target = target
    }
}
