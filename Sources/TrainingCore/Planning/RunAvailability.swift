/// When the athlete can run: the ``DaySlot``s that are free on each ``Weekday``.
///
/// Availability is a fact about the athlete, not a choice made for one plan, so it is a value of its
/// own that can be stored and edited as a single global setting. A plan's ``PlanPreferences`` carries
/// a copy of it as the generator's input. A weekday without slots (absent, or set to an empty set)
/// means no running that day; ``Weekday/monday`` and friends are the calendar weekday regardless of
/// ``AthleteProfile/weekStartsOn``.
///
/// Each free slot can also carry ``SlotOptions`` (whether a long run fits, whether a track is
/// available); a slot without stored options has ``SlotOptions/default``.
public struct RunAvailability: Sendable, Codable, Hashable {
    /// The free slots per weekday. A weekday never maps to an empty set: empty entries are removed.
    public private(set) var slots: [Weekday: Set<DaySlot>]

    /// The options of the slots that differ from ``SlotOptions/default``. Slots at the defaults have
    /// no entry, so read them through ``subscript(_:_:)``.
    public private(set) var slotOptions: [Weekday: [DaySlot: SlotOptions]]

    /// Creates availability from the free slots per weekday.
    ///
    /// - Parameters:
    ///   - slots: The free slots per weekday. Weekdays with an empty set are dropped. Defaults to no
    ///     availability on any day.
    ///   - slotOptions: The options per weekday and slot. Entries equal to ``SlotOptions/default``
    ///     are dropped. Defaults to the default options on every slot.
    public init(slots: [Weekday: Set<DaySlot>] = [:], slotOptions: [Weekday: [DaySlot: SlotOptions]] = [:]) {
        self.slots = slots.filter { !$0.value.isEmpty }
        self.slotOptions = Self.sparse(slotOptions)
    }

    private static func sparse(_ options: [Weekday: [DaySlot: SlotOptions]]) -> [Weekday: [DaySlot: SlotOptions]] {
        options.compactMapValues { perSlot in
            let kept = perSlot.filter { $0.value != .default }
            return kept.isEmpty ? nil : kept
        }
    }

    /// The options of a slot on a weekday; ``SlotOptions/default`` when none are stored.
    ///
    /// Assigning ``SlotOptions/default`` removes the stored entry.
    public subscript(weekday: Weekday, slot: DaySlot) -> SlotOptions {
        get { slotOptions[weekday]?[slot] ?? .default }
        set {
            var perSlot = slotOptions[weekday] ?? [:]
            perSlot[slot] = newValue == .default ? nil : newValue
            slotOptions[weekday] = perSlot.isEmpty ? nil : perSlot
        }
    }

    /// The free slots on a weekday; an empty set means the athlete does not run that day.
    ///
    /// Assigning an empty set removes the weekday.
    public subscript(weekday: Weekday) -> Set<DaySlot> {
        get { slots[weekday] ?? [] }
        set { slots[weekday] = newValue.isEmpty ? nil : newValue }
    }

    private enum CodingKeys: String, CodingKey {
        case slots, slotOptions
    }

    /// Decodes availability, ignoring weekdays and slots this version does not know (for instance
    /// written by a newer version) and treating a missing `slots` as no availability and a missing
    /// `slotOptions` as the default options on every slot. Saving it again writes only what was
    /// understood, so the unknown values are lost.
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

        let rawOptions = try container.decodeIfPresent([String: [String: SlotOptions]].self, forKey: .slotOptions) ?? [:]
        var decodedOptions: [Weekday: [DaySlot: SlotOptions]] = [:]
        for (key, perSlot) in rawOptions {
            guard let rawValue = Int(key), let weekday = Weekday(rawValue: rawValue) else { continue }
            for (name, options) in perSlot {
                guard let slot = DaySlot(rawValue: name) else { continue }
                decodedOptions[weekday, default: [:]][slot] = options
            }
        }
        slotOptions = Self.sparse(decodedOptions)
    }

    /// Encodes the slots keyed by the weekday's raw value (1 = Sunday), with slot names sorted so the
    /// output is stable, and the non-default slot options keyed the same way.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let raw = Dictionary(uniqueKeysWithValues: slots.map { weekday, daySlots in
            (String(weekday.rawValue), daySlots.map(\.rawValue).sorted())
        })
        try container.encode(raw, forKey: .slots)
        if !slotOptions.isEmpty {
            let rawOptions = Dictionary(uniqueKeysWithValues: slotOptions.map { weekday, perSlot in
                (String(weekday.rawValue), Dictionary(uniqueKeysWithValues: perSlot.map { ($0.key.rawValue, $0.value) }))
            })
            try container.encode(rawOptions, forKey: .slotOptions)
        }
    }
}
