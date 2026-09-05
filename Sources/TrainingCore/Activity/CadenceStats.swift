/// Summarized cadence for an ``Activity``, computed once by the importing source rather than
/// stored as a raw cadence-over-time stream.
///
/// Units depend on the sport (steps per minute for running/walking, revolutions per minute for
/// cycling) — `TrainingCore` stays sport-agnostic here the same way ``PaceModel``'s zone
/// multipliers do, leaving unit interpretation to the caller/UI.
public struct CadenceStats: Sendable, Codable, Hashable {
    public var min: Double
    public var max: Double
    public var mean: Double
    public var median: Double

    public init(min: Double, max: Double, mean: Double, median: Double) {
        self.min = min
        self.max = max
        self.mean = mean
        self.median = median
    }
}
