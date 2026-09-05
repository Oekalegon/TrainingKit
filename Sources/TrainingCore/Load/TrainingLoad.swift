/// A single training-load value, in TRIMP units, with its provenance.
public struct TrainingLoad: Sendable, Codable, Hashable {
    public var value: Double
    public var method: LoadMethod
    /// 1.0 for measured loads; less than 1 for estimates, used by MVP 3 calibration.
    public var confidence: Double

    public init(value: Double, method: LoadMethod, confidence: Double = 1.0) {
        self.value = value
        self.method = method
        self.confidence = confidence
    }
}
