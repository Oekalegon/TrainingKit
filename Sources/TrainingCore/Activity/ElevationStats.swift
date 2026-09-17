/// Summarized elevation for an ``Activity``, computed once by the importing source rather than
/// stored as a raw elevation-over-time stream — `TrainingCore` has no current need for the shape
/// of elevation over time, only these aggregate numbers.
public struct ElevationStats: Sendable, Codable, Hashable {
    /// Total climbed, in meters.
    public var gainMeters: Double
    /// Total descended, in meters.
    public var lossMeters: Double
    /// The lowest recorded elevation, in meters.
    public var minMeters: Double
    /// The highest recorded elevation, in meters.
    public var maxMeters: Double

    /// Creates an elevation summary.
    ///
    /// - Parameters:
    ///   - gainMeters: Total climbed, in meters.
    ///   - lossMeters: Total descended, in meters.
    ///   - minMeters: The lowest recorded elevation, in meters.
    ///   - maxMeters: The highest recorded elevation, in meters.
    public init(gainMeters: Double, lossMeters: Double, minMeters: Double, maxMeters: Double) {
        self.gainMeters = gainMeters
        self.lossMeters = lossMeters
        self.minMeters = minMeters
        self.maxMeters = maxMeters
    }
}
