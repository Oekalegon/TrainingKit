/// A group of ``WorkoutStep``s repeated as a unit, e.g. "6 x (400m work, 200m recovery)".
///
/// `repetitions` is 1 for a plain warmup/cooldown block and N for an interval set.
public struct WorkoutBlock: Sendable, Codable, Hashable {
    /// The steps making up one repetition of this block.
    public var steps: [WorkoutStep]
    /// How many times `steps` repeats.
    public var repetitions: Int

    /// Creates a workout block.
    ///
    /// - Parameters:
    ///   - steps: The steps making up one repetition of this block.
    ///   - repetitions: How many times `steps` repeats; defaults to 1.
    public init(steps: [WorkoutStep], repetitions: Int = 1) {
        self.steps = steps
        self.repetitions = repetitions
    }
}
