import Foundation

/// A completed activity, imported or entered manually.
///
/// Heart-rate samples are kept on the activity, not just the resulting ``TrainingLoad``, so a
/// recalculation with a changed `maxHeartRateBPM` or a different ``LoadCalculator`` is possible
/// without re-importing.
public struct Activity: Identifiable, Sendable, Codable {
    public let id: UUID
    public var source: ActivitySource
    public var sport: Sport
    public var start: Date
    public var duration: TimeInterval
    public var distanceMeters: Double?
    /// May be empty for sports/sources without heart-rate data; see ``DurationRPECalculator``.
    public var heartRate: [HeartRateSample]
    /// Borg CR10 rating of perceived exertion (1...10), used by ``DurationRPECalculator`` when
    /// no heart-rate data is available.
    public var perceivedExertion: Int?
    /// Set by ``PlanReconciler`` once this activity is matched to a ``PlannedActivity``.
    public var linkedPlanID: UUID?

    public init(
        id: UUID = UUID(),
        source: ActivitySource,
        sport: Sport,
        start: Date,
        duration: TimeInterval,
        distanceMeters: Double? = nil,
        heartRate: [HeartRateSample] = [],
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
        self.perceivedExertion = perceivedExertion
        self.linkedPlanID = linkedPlanID
    }
}
