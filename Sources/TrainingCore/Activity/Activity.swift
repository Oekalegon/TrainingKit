import Foundation

/// A completed activity, imported or entered manually.
///
/// Heart-rate and speed samples are kept on the activity, not just the resulting
/// ``TrainingLoad``, so a recalculation with a changed `maxHeartRateBPM` or a different
/// ``LoadCalculator`` is possible without re-importing. Elevation, cadence, and the geographic
/// area covered are kept as one-time summaries rather than raw streams — see ``ElevationStats``,
/// ``CadenceStats``, and ``GeographicBounds`` for why.
public struct Activity: Identifiable, Sendable, Codable, Hashable {
    /// A stable identifier for this activity, independent of ``source``.
    public let id: UUID
    /// Where this activity came from, and the key used to dedupe re-imports.
    public var source: ActivitySource
    /// The kind of activity performed.
    public var sport: Sport
    /// When the activity began.
    public var start: Date
    /// How long the activity lasted.
    public var duration: TimeInterval
    /// Total distance covered, if the source/sport reports one.
    public var distanceMeters: Double?
    /// May be empty for sports/sources without heart-rate data; see ``DurationRPECalculator``.
    public var heartRate: [HeartRateSample]
    /// May be empty for sports/sources without speed data (e.g. indoor strength training).
    public var speed: [SpeedSample]
    /// Summarized elevation, if the source reports one; see ``ElevationStats``.
    public var elevation: ElevationStats?
    /// Summarized cadence, if the source reports one; see ``CadenceStats``.
    public var cadence: CadenceStats?
    /// The geographic area this activity took place within, if the source reports GPS data.
    public var geographicBounds: GeographicBounds?
    /// Borg CR10 rating of perceived exertion (1...10), used by ``DurationRPECalculator`` when
    /// no heart-rate data is available.
    public var perceivedExertion: Int?
    /// Set by ``PlanReconciler`` once this activity is matched to a ``PlannedActivity``.
    public var linkedPlanID: UUID?

    /// Creates a completed activity.
    ///
    /// - Parameters:
    ///   - id: A stable identifier; defaults to a new random `UUID`.
    ///   - source: Where this activity came from.
    ///   - sport: The kind of activity performed.
    ///   - start: When the activity began.
    ///   - duration: How long the activity lasted.
    ///   - distanceMeters: Total distance covered, if known.
    ///   - heartRate: Raw heart-rate samples, if any.
    ///   - speed: Raw speed samples, if any.
    ///   - elevation: Summarized elevation, if known.
    ///   - cadence: Summarized cadence, if known.
    ///   - geographicBounds: The geographic area covered, if known.
    ///   - perceivedExertion: Borg CR10 rating (1...10), if entered.
    ///   - linkedPlanID: The matched ``PlannedActivity``'s id, if already reconciled.
    public init(
        id: UUID = UUID(),
        source: ActivitySource,
        sport: Sport,
        start: Date,
        duration: TimeInterval,
        distanceMeters: Double? = nil,
        heartRate: [HeartRateSample] = [],
        speed: [SpeedSample] = [],
        elevation: ElevationStats? = nil,
        cadence: CadenceStats? = nil,
        geographicBounds: GeographicBounds? = nil,
        perceivedExertion: Int? = nil,
        linkedPlanID: UUID? = nil
    ) {
        self.id = id
        self.source = source
        self.sport = sport
        self.start = start
        self.duration = duration
        self.distanceMeters = distanceMeters
        self.heartRate = heartRate
        self.speed = speed
        self.elevation = elevation
        self.cadence = cadence
        self.geographicBounds = geographicBounds
        self.perceivedExertion = perceivedExertion
        self.linkedPlanID = linkedPlanID
    }
}
