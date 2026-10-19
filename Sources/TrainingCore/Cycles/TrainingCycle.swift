import Foundation

/// A macro-, meso-, or micro-cycle: the calendar structure that plans and statistics hang off.
///
/// Rules enforced by ``CycleStore`` on insert: a child's `dateRange` must lie inside its parent's,
/// and siblings (cycles sharing the same `parentID` and `planID`) must not overlap. Micros are not required to
/// be exactly 7 days — a 10-day micro is legitimate. Gaps are allowed; untracked time is just no
/// cycle.
public struct TrainingCycle: Identifiable, Sendable, Codable, Hashable {
    /// A stable identifier for this cycle.
    public let id: UUID
    /// Where this cycle sits in the macro/meso/micro hierarchy.
    public var level: CycleLevel
    /// This cycle's training emphasis.
    public var phase: CyclePhase
    /// How hard this micro is meant to be (build, recovery or taper; `race` only on cycles stored before layouts dropped it). Only micro-level cycles
    /// carry one; it is `nil` for macro- and meso-level cycles (any role passed for them is dropped).
    public var loadRole: MicroLoadRole?
    /// A display name, e.g. "Ultra prep 2027", "Meso 3", "Week 11".
    public var name: String
    /// Day-granular date range, in the athlete's timezone.
    public var dateRange: ClosedRange<Date>
    /// The parent cycle this one nests inside (micro → meso → macro), if any.
    public var parentID: UUID?
    /// The ``Race`` this cycle's macro/meso targets, if any. Only macro- and meso-level cycles set
    /// this; a micro doesn't carry its own copy since it can always be read from its meso parent.
    public var targetRaceID: UUID?
    /// The ``TrainingPlan`` this cycle belongs to. `nil` for a cycle stored before plans existed;
    /// ``TrainingModel`` adopts those into a plan. Sibling cycles only have to avoid overlapping
    /// within the same plan, so two plans can lay out the same weeks differently.
    public var planID: UUID?

    /// Creates a training cycle.
    ///
    /// - Parameters:
    ///   - id: A stable identifier; defaults to a new random `UUID`.
    ///   - level: Where this cycle sits in the macro/meso/micro hierarchy.
    ///   - phase: This cycle's training emphasis.
    ///   - loadRole: The micro's load role. Macro and meso cycles have none. For a micro, `nil` (the
    ///     default) derives it from `phase` the way legacy payloads are decoded — `build`,
    ///     `recovery`, `taper` and `race` map to the role of the same name, any other phase to `build`.
    ///   - name: A display name.
    ///   - dateRange: Day-granular date range, in the athlete's timezone.
    ///   - parentID: The parent cycle this one nests inside, if any.
    ///   - targetRaceID: The race this cycle targets, if any.
    ///   - planID: The training plan this cycle belongs to, if any.
    public init(
        id: UUID = UUID(),
        level: CycleLevel,
        phase: CyclePhase,
        loadRole: MicroLoadRole? = nil,
        name: String,
        dateRange: ClosedRange<Date>,
        parentID: UUID? = nil,
        targetRaceID: UUID? = nil,
        planID: UUID? = nil
    ) {
        self.id = id
        self.level = level
        self.phase = phase
        self.loadRole = level == .micro ? loadRole ?? MicroLoadRole(legacyPhase: phase) : nil
        self.name = name
        self.dateRange = dateRange
        self.parentID = parentID
        self.targetRaceID = targetRaceID
        self.planID = planID
    }

    private enum CodingKeys: String, CodingKey {
        case id, level, phase, loadRole, name, dateRange, parentID, targetRaceID, planID
    }

    /// Decodes a cycle, including payloads written before the load role existed. For those, a
    /// micro's role is derived from its stored phase (`build`, `recovery`, `taper` and `race` map
    /// to the role of the same name; any other phase counts as `build`). A stored recovery micro
    /// keeps its `recovery` phase, whereas a micro laid out now takes its block's phase and
    /// carries the recovery role instead.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        level = try container.decode(CycleLevel.self, forKey: .level)
        phase = try container.decode(CyclePhase.self, forKey: .phase)
        name = try container.decode(String.self, forKey: .name)
        dateRange = try container.decode(ClosedRange<Date>.self, forKey: .dateRange)
        parentID = try container.decodeIfPresent(UUID.self, forKey: .parentID)
        targetRaceID = try container.decodeIfPresent(UUID.self, forKey: .targetRaceID)
        planID = try container.decodeIfPresent(UUID.self, forKey: .planID)
        if let stored = try container.decodeIfPresent(MicroLoadRole.self, forKey: .loadRole) {
            loadRole = stored
        } else if level == .micro {
            loadRole = MicroLoadRole(legacyPhase: phase)
        } else {
            loadRole = nil
        }
    }
}
