/// When the athlete can run: the ``DaySlot``s that are free on each ``Weekday``.
///
/// Availability is a fact about the athlete, not a choice made for one plan, so it is a value of its
/// own that can be stored and edited as a single global setting. A plan's ``PlanPreferences`` carries
/// a copy of it as the generator's input. A weekday without slots (absent, or set to an empty set)
/// means no running that day; ``Weekday/monday`` and friends are the calendar weekday regardless of
/// ``AthleteProfile/weekStartsOn``.
public struct RunAvailability: Sendable, Codable, Hashable {
    /// The free slots per weekday. A weekday never maps to an empty set: empty entries are removed.
    public private(set) var slots: [Weekday: Set<DaySlot>]

    /// Creates availability from the free slots per weekday.
    ///
    /// - Parameter slots: The free slots per weekday. Weekdays with an empty set are dropped.
    ///   Defaults to no availability on any day.
    public init(slots: [Weekday: Set<DaySlot>] = [:]) {
        self.slots = slots.filter { !$0.value.isEmpty }
    }

    /// The free slots on a weekday; an empty set means the athlete does not run that day.
    ///
    /// Assigning an empty set removes the weekday.
    public subscript(weekday: Weekday) -> Set<DaySlot> {
        get { slots[weekday] ?? [] }
        set { slots[weekday] = newValue.isEmpty ? nil : newValue }
    }

    private enum CodingKeys: String, CodingKey {
        case slots
    }

    /// Decodes availability, ignoring weekdays and slots this version does not know (for instance
    /// written by a newer version) and treating a missing `slots` as no availability. Saving it again
    /// writes only what was understood, so the unknown values are lost.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decodeIfPresent([String: [String]].self, forKey: .slots) ?? [:]
        var decoded: [Weekday: Set<DaySlot>] = [:]
        for (key, names) in raw {
            guard let rawValue = Int(key), let weekday = Weekday(rawValue: rawValue) else { continue }
            let known = Set(names.compactMap(DaySlot.init(rawValue:)))
            if !known.isEmpty { decoded[weekday] = known }
        }
        slots = decoded
    }

    /// Encodes the slots keyed by the weekday's raw value (1 = Sunday), with slot names sorted so the
    /// output is stable.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let raw = Dictionary(uniqueKeysWithValues: slots.map { weekday, daySlots in
            (String(weekday.rawValue), daySlots.map(\.rawValue).sorted())
        })
        try container.encode(raw, forKey: .slots)
    }
}
