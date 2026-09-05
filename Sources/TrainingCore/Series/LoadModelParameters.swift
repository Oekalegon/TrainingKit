/// Tunable time constants for ``FitnessMetricsCalculator``'s EWMA model.
public struct LoadModelParameters: Sendable, Codable, Hashable {
    public var ctlTimeConstantDays: Double
    public var atlTimeConstantDays: Double
    public var monotonyWindowDays: Int

    public init(ctlTimeConstantDays: Double = 42, atlTimeConstantDays: Double = 7, monotonyWindowDays: Int = 7) {
        self.ctlTimeConstantDays = ctlTimeConstantDays
        self.atlTimeConstantDays = atlTimeConstantDays
        self.monotonyWindowDays = monotonyWindowDays
    }
}
