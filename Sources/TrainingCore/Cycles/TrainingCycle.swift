import Foundation

/// A macro-, meso-, or micro-cycle: the calendar structure that plans and statistics hang off.
///
/// Rules enforced by ``CycleStore`` on insert: a child's `dateRange` must lie inside its parent's,
/// and siblings (cycles sharing the same `parentID`) must not overlap. Micros are not required to
/// be exactly 7 days — a 10-day micro is legitimate. Gaps are allowed; untracked time is just no
/// cycle.
public struct TrainingCycle: Identifiable, Sendable, Codable, Hashable {
    /// A stable identifier for this cycle.
    public let id: UUID
    /// Where this cycle sits in the macro/meso/micro hierarchy.
    public var level: CycleLevel
    /// This cycle's training emphasis.
    public var phase: CyclePhase
    /// A display name, e.g. "Ultra prep 2027", "Meso 3", "Week 11".
    public var name: String
    /// Day-granular date range, in the athlete's timezone.
    public var dateRange: ClosedRange<Date>
    /// The parent cycle this one nests inside (micro → meso → macro), if any.
    public var parentID: UUID?
    /// The ``Race`` this cycle's macro/meso targets, if any. Only macro- and meso-level cycles set
    /// this; a micro doesn't carry its own copy since it can always be read from its meso parent.
    public var targetRaceID: UUID?

    /// Creates a training cycle.
    ///
    /// - Parameters:
    ///   - id: A stable identifier; defaults to a new random `UUID`.
    ///   - level: Where this cycle sits in the macro/meso/micro hierarchy.
    ///   - phase: This cycle's training emphasis.
    ///   - name: A display name.
    ///   - dateRange: Day-granular date range, in the athlete's timezone.
    ///   - parentID: The parent cycle this one nests inside, if any.
    ///   - targetRaceID: The race this cycle targets, if any.
    public init(
        id: UUID = UUID(),
        level: CycleLevel,
        phase: CyclePhase,
        name: String,
        dateRange: ClosedRange<Date>,
        parentID: UUID? = nil,
        targetRaceID: UUID? = nil
    ) {
        self.id = id
        self.level = level
        self.phase = phase
        self.name = name
        self.dateRange = dateRange
        self.parentID = parentID
        self.targetRaceID = targetRaceID
    }
}
