import Foundation

/// One planned session as the paradigm rules of ``PlanEvaluator`` see it.
///
/// The evaluator works on already-described sessions, not on workouts, so it stays a pure function;
/// ``PlannedIntensityClassifier/session(on:for:athlete:)`` builds one from a ``StructuredWorkout``.
public struct PlanSession: Sendable, Codable, Hashable {
    private enum CodingKeys: String, CodingKey {
        case day, seconds, intensity, speed, isLongRun
    }

    /// Decodes a session; `isLongRun` is optional and defaults to `false`.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        day = try container.decode(Date.self, forKey: .day)
        seconds = try container.decode(TimeInterval.self, forKey: .seconds)
        intensity = try container.decode(IntensityCategory.self, forKey: .intensity)
        speed = try container.decode(SpeedLevel.self, forKey: .speed)
        isLongRun = try container.decodeIfPresent(Bool.self, forKey: .isLongRun) ?? false
    }

    /// The calendar day of the session, day-granular in the same timezone as the metrics it is
    /// evaluated with.
    public let day: Date
    /// The planned duration in seconds; the weight of the session in a distribution.
    public let seconds: TimeInterval
    /// The session's intensity from its time in zones.
    public let intensity: IntensityCategory
    /// The session's fastest work, independent of `intensity`.
    public let speed: SpeedLevel
    /// Whether this is the long run of its micro. It says nothing about intensity: a long run is
    /// easy by ``intensity`` but may still count towards hard-session spacing, see
    /// ``TrainingParadigm/spacesLongRunsAsHard``.
    public let isLongRun: Bool

    /// Creates a planned session.
    ///
    /// - Parameters:
    ///   - day: The calendar day of the session.
    ///   - seconds: The planned duration in seconds.
    ///   - intensity: The session's intensity from its time in zones.
    ///   - speed: The session's fastest work.
    ///   - isLongRun: Whether this is the long run of its micro; defaults to `false`.
    public init(day: Date, seconds: TimeInterval, intensity: IntensityCategory, speed: SpeedLevel, isLongRun: Bool = false) {
        self.day = day
        self.seconds = seconds
        self.intensity = intensity
        self.speed = speed
        self.isLongRun = isLongRun
    }
}
