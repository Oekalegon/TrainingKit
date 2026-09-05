/// A group of ``WorkoutStep``s repeated as a unit, e.g. "6 x (400m work, 200m recovery)".
///
/// `repetitions` is 1 for a plain warmup/cooldown block and N for an interval set.
public struct WorkoutBlock: Sendable, Codable, Hashable {
    public var steps: [WorkoutStep]
    public var repetitions: Int

    public init(steps: [WorkoutStep], repetitions: Int = 1) {
        self.steps = steps
        self.repetitions = repetitions
    }
}
