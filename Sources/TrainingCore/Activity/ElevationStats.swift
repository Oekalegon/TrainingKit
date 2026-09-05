/// Summarized elevation for an ``Activity``, computed once by the importing source rather than
/// stored as a raw elevation-over-time stream — `TrainingCore` has no current need for the shape
/// of elevation over time, only these aggregate numbers.
public struct ElevationStats: Sendable, Codable, Hashable {
    public var gainMeters: Double
    public var lossMeters: Double
    public var minMeters: Double
    public var maxMeters: Double

    public init(gainMeters: Double, lossMeters: Double, minMeters: Double, maxMeters: Double) {
        self.gainMeters = gainMeters
        self.lossMeters = lossMeters
        self.minMeters = minMeters
        self.maxMeters = maxMeters
    }
}
