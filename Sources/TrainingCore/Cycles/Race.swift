import Foundation

/// A target race a training cycle is built around.
///
/// A dated event with a ``RacePriority``. It anchors a ``CycleLayoutBuilder`` layout and the
/// race-day TSB rule in ``PlanEvaluator``; a non-event target with no date is a separate ``Goal``.
public struct Race: Identifiable, Sendable, Codable, Hashable {
    /// A stable identifier for this race.
    public let id: UUID
    /// The race's display name.
    public var name: String
    /// The calendar day the race takes place, in the athlete's timezone.
    public var date: Date
    /// How much this race matters to the athlete; see ``KeyRaceLayout``.
    public var priority: RacePriority
    /// The intensity the race's specific-phase work is aimed at, or `nil` for none (MVP5-114).
    ///
    /// Nothing reads it yet. A stored race without the field decodes to `nil`, and so does one whose
    /// target is of a kind this version doesn't know or fails ``SpecificPhaseTarget/validate()``,
    /// so a newer device's data never loses the race.
    public var specificPhaseTarget: SpecificPhaseTarget?

    /// Creates a race.
    ///
    /// - Parameters:
    ///   - id: A stable identifier; defaults to a new random `UUID`.
    ///   - name: The race's display name.
    ///   - date: The calendar day the race takes place, in the athlete's timezone.
    ///   - priority: How much this race matters to the athlete; see ``KeyRaceLayout``.
    ///   - specificPhaseTarget: The intensity the specific-phase work is aimed at; defaults to `nil`, none.
    public init(
        id: UUID = UUID(), name: String, date: Date, priority: RacePriority,
        specificPhaseTarget: SpecificPhaseTarget? = nil
    ) {
        self.id = id
        self.name = name
        self.date = date
        self.priority = priority
        self.specificPhaseTarget = specificPhaseTarget
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, date, priority, specificPhaseTarget
    }

    /// Decodes a race; see ``specificPhaseTarget`` for how a missing, unknown or invalid target decodes.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        date = try container.decode(Date.self, forKey: .date)
        priority = try container.decode(RacePriority.self, forKey: .priority)
        specificPhaseTarget = try? container.decodeIfPresent(SpecificPhaseTarget.self, forKey: .specificPhaseTarget)
    }
}
