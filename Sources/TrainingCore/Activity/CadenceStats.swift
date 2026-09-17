/// Summarized cadence for an ``Activity``, computed once by the importing source rather than
/// stored as a raw cadence-over-time stream.
///
/// Units depend on the sport (steps per minute for running/walking, revolutions per minute for
/// cycling) — `TrainingCore` stays sport-agnostic here the same way ``PaceModel``'s zone
/// multipliers do, leaving unit interpretation to the caller/UI.
public struct CadenceStats: Sendable, Codable, Hashable {
    /// The lowest recorded cadence.
    public var min: Double
    /// The highest recorded cadence.
    public var max: Double
    /// The arithmetic mean cadence.
    public var mean: Double
    /// The median cadence.
    public var median: Double

    /// Creates a cadence summary.
    ///
    /// - Parameters:
    ///   - min: The lowest recorded cadence.
    ///   - max: The highest recorded cadence.
    ///   - mean: The arithmetic mean cadence.
    ///   - median: The median cadence.
    public init(min: Double, max: Double, mean: Double, median: Double) {
        self.min = min
        self.max = max
        self.mean = mean
        self.median = median
    }
}
