import Foundation

/// A target race a training cycle is built around.
///
/// Just enough to anchor a ``CycleLayoutBuilder`` layout and, later, the race-day TSB rule
/// (`PlanEvaluator`, MVP 2) — `Goal`/richer race metadata are MVP 2 additions.
public struct Race: Identifiable, Sendable, Codable, Hashable {
    /// A stable identifier for this race.
    public let id: UUID
    /// The race's display name.
    public var name: String
    /// The calendar day the race takes place, in the athlete's timezone.
    public var date: Date
    /// How much this race matters, for taper sizing.
    public var priority: RacePriority

    /// Creates a race.
    ///
    /// - Parameters:
    ///   - id: A stable identifier; defaults to a new random `UUID`.
    ///   - name: The race's display name.
    ///   - date: The calendar day the race takes place, in the athlete's timezone.
    ///   - priority: How much this race matters, for taper sizing.
    public init(id: UUID = UUID(), name: String, date: Date, priority: RacePriority) {
        self.id = id
        self.name = name
        self.date = date
        self.priority = priority
    }
}
