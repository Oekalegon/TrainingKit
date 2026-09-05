/// A single training-load value, in TRIMP units, with its provenance.
public struct TrainingLoad: Sendable, Codable, Hashable {
    /// The load value, in TRIMP units.
    public var value: Double
    /// How this value was computed; see ``LoadMethod``.
    public var method: LoadMethod
    /// 1.0 for measured loads; less than 1 for estimates, used by MVP 3 calibration.
    public var confidence: Double

    /// Creates a training load.
    ///
    /// - Parameters:
    ///   - value: The load value, in TRIMP units.
    ///   - method: How this value was computed.
    ///   - confidence: 1.0 for measured loads; less than 1 for estimates. Defaults to 1.0.
    public init(value: Double, method: LoadMethod, confidence: Double = 1.0) {
        self.value = value
        self.method = method
        self.confidence = confidence
    }
}
