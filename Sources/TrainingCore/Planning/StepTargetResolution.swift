/// The result of ``StepTargetResolver/resolve(_:on:athlete:raceTarget:raceTargetFraction:)``.
public struct StepTargetResolution: Sendable, Codable, Hashable {
    /// The workout with concrete targets written into its steps. Steps that could not be resolved
    /// keep the target they had.
    public let workout: StructuredWorkout
    /// The steps that could not be fully resolved, in workout order; empty when everything was.
    public let unresolved: [UnresolvedStep]

    /// Creates a resolution.
    ///
    /// - Parameters:
    ///   - workout: The workout with resolved targets.
    ///   - unresolved: The steps that could not be fully resolved.
    public init(workout: StructuredWorkout, unresolved: [UnresolvedStep]) {
        self.workout = workout
        self.unresolved = unresolved
    }
}
