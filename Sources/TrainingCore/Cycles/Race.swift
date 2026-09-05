import Foundation

/// How much a race matters, used to size its taper and — in MVP 1's `PlanEvaluator` (not yet
/// built) — the injury-risk/progress guardrails checked against it.
public enum RacePriority: Sendable, Codable, Hashable, CaseIterable {
    /// The primary goal race a macrocycle is built around; the layout tapers fully for it.
    case a
    /// An important tune-up race; MVP 1 treats it like an A race for layout purposes, but this
    /// distinction exists for MVP 2's differentiated taper/guardrail handling.
    case b
    /// A low-priority or training race, raced through rather than tapered for; not yet
    /// differentiated from `.a`/`.b` until MVP 2.
    case c
}

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
