/// Errors thrown by a ``LoadCalculator`` when it cannot compute a load for an activity.
public enum LoadError: Error, Sendable, Equatable {
    /// The activity has no heart-rate samples; callers should fall back to a calculator that
    /// doesn't need them, e.g. ``DurationRPECalculator``.
    case noHeartRateData
    /// A heart-rate sample was NaN or negative.
    case invalidHeartRateData(reason: String)
    /// The activity has no `perceivedExertion`, so ``DurationRPECalculator`` cannot score it.
    case missingPerceivedExertion
    /// The athlete has no ``HeartRateZoneSettings`` on record at all, so no heart-rate-reserve
    /// ratio can be computed for the activity's date.
    case missingHeartRateZoneSettings
}
