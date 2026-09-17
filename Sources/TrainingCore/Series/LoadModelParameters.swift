/// Tunable time constants for ``FitnessMetricsCalculator``'s EWMA model.
public struct LoadModelParameters: Sendable, Codable, Hashable {
    /// The CTL (chronic training load) EWMA time constant, in days. Defaults to 42.
    public var ctlTimeConstantDays: Double
    /// The ATL (acute training load) EWMA time constant, in days. Defaults to 7.
    public var atlTimeConstantDays: Double
    /// The trailing window length, in days, used for monotony and strain. Defaults to 7.
    public var monotonyWindowDays: Int

    /// Creates a set of load model parameters, defaulting to the standard Banister time constants.
    ///
    /// - Parameters:
    ///   - ctlTimeConstantDays: The CTL EWMA time constant, in days.
    ///   - atlTimeConstantDays: The ATL EWMA time constant, in days.
    ///   - monotonyWindowDays: The trailing window length, in days, for monotony and strain.
    public init(ctlTimeConstantDays: Double = 42, atlTimeConstantDays: Double = 7, monotonyWindowDays: Int = 7) {
        self.ctlTimeConstantDays = ctlTimeConstantDays
        self.atlTimeConstantDays = atlTimeConstantDays
        self.monotonyWindowDays = monotonyWindowDays
    }
}
