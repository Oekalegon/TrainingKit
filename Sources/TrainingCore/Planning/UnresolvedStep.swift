/// A step ``StepTargetResolver`` could not fully resolve, and why.
public struct UnresolvedStep: Sendable, Codable, Hashable {
    /// The position of the step's block in ``StructuredWorkout/blocks``.
    public let blockIndex: Int
    /// The position of the step in ``WorkoutBlock/steps``.
    public let stepIndex: Int
    /// Why the step was not resolved.
    public let reason: UnresolvedReason

    /// Creates an entry.
    ///
    /// - Parameters:
    ///   - blockIndex: The position of the step's block.
    ///   - stepIndex: The position of the step in its block.
    ///   - reason: Why the step was not resolved.
    public init(blockIndex: Int, stepIndex: Int, reason: UnresolvedReason) {
        self.blockIndex = blockIndex
        self.stepIndex = stepIndex
        self.reason = reason
    }
}
