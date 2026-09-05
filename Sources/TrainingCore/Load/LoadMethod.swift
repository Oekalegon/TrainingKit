/// How a ``TrainingLoad`` value was computed.
public enum LoadMethod: Sendable, Codable, Hashable {
    /// Banister's exponential heart-rate TRIMP, integrated over measured heart-rate samples.
    case exponentialTRIMP
    /// Session-RPE: duration in minutes multiplied by rating of perceived exertion.
    case durationRPE
    /// Estimated from a planned workout rather than measured, via ``PlannedLoadEstimator``.
    case estimatedFromPlan
    /// Entered directly by the user.
    case manual
}
