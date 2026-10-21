/// A single step within a ``WorkoutBlock``, e.g. "5 minutes warmup" or "400m at Zone 4".
public struct WorkoutStep: Sendable, Codable, Hashable {
    /// The role this step plays within its block.
    public var kind: StepKind
    /// What ends this step.
    public var goal: StepGoal
    /// The intensity this step targets, if any.
    public var target: IntensityTarget?
    /// A second target shown alongside ``target`` (MVP5-122), or `nil`. ``StepTargetResolver`` sets it
    /// to the pace to run for a heart-rate step, so the athlete sees both. Planning load, durations
    /// and the WorkoutKit alert read ``target`` only. Absent from steps saved before this field
    /// existed, which decode as `nil`.
    public var companionTarget: IntensityTarget?

    /// Creates a workout step.
    ///
    /// - Parameters:
    ///   - kind: The role this step plays within its block.
    ///   - goal: What ends this step.
    ///   - target: The intensity this step targets, if any.
    ///   - companionTarget: A second target shown alongside `target`; defaults to `nil`.
    public init(kind: StepKind, goal: StepGoal, target: IntensityTarget? = nil, companionTarget: IntensityTarget? = nil) {
        self.kind = kind
        self.goal = goal
        self.target = target
        self.companionTarget = companionTarget
    }
}
