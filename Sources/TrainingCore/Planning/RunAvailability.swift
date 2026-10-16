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
///
/// How many runs the athlete wants on a day is stated explicitly (``runs(on:)``, default 1), not
/// inferred from the free parts: two free parts do not by themselves mean a two-a-day. The
/// generator (MVP5-119) places that many runs on the day, each in its own free part, so a day never
/// has more runs than free parts. Read the number through ``runs(on:)``,
/// which applies that cap, rather than ``runsPerDay``.
///
/// Availability stored with the former combined `afternoonEvening` slot decodes to both
/// ``DaySlot/afternoon`` and ``DaySlot/evening``, with its options on both, so it keeps its meaning.
public struct RunAvailability: Sendable, Codable, Hashable {
    /// The free slots per weekday. A weekday never maps to an empty set: empty entries are removed.
    public private(set) var slots: [Weekday: Set<DaySlot>]

    /// The options of the slots that differ from ``SlotOptions/default``. Slots at the defaults have
    /// no entry, so read them through ``subscript(_:_:)``.
    public private(set) var slotOptions: [Weekday: [DaySlot: SlotOptions]]

    /// The stored number of runs per weekday, only for the days where it is above 1 (the default).
    /// Not capped by the free slots, so it is kept when parts are removed and re-added; read the
    /// effective number through ``runs(on:)``.
    public private(set) var runsPerDay: [Weekday: Int]

    /// Creates availability from the free slots per weekday.
    ///
    /// - Parameters:
    ///   - slots: The free slots per weekday. Weekdays with an empty set are dropped. Defaults to no
    ///     availability on any day.
    ///   - slotOptions: The options per weekday and slot. Entries equal to ``SlotOptions/default``
    ///     are dropped. Defaults to the default options on every slot.
    ///   - runsPerDay: The number of runs per weekday. Values of 1 or less are dropped (a day has at
    ///     least one run, the default). Defaults to one run on every day.
    public init(
        slots: [Weekday: Set<DaySlot>] = [:],
        slotOptions: [Weekday: [DaySlot: SlotOptions]] = [:],
        runsPerDay: [Weekday: Int] = [:]
    ) {
        self.slots = slots.filter { !$0.value.isEmpty }
        self.slotOptions = Self.sparse(slotOptions)
        self.runsPerDay = runsPerDay.filter { $0.value > 1 }
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

    /// The number of runs the athlete wants on a weekday: 0 on a day without free slots, otherwise
    /// the stored number (1 when none is stored) capped at the number of free slots.
    public func runs(on weekday: Weekday) -> Int {
        min(runsPerDay[weekday] ?? 1, slots[weekday]?.count ?? 0)
    }

    /// Sets the number of runs wanted on a weekday.
    ///
    /// The number is kept as given, so it is not lost when slots are removed and returns when they
    /// are added again; ``runs(on:)`` applies the cap. A count of 1 or less sets the default of one
    /// run and removes the stored entry.
    ///
    /// - Parameters:
    ///   - count: The number of runs.
    ///   - weekday: The weekday it applies to.
    public mutating func setRuns(_ count: Int, on weekday: Weekday) {
        runsPerDay[weekday] = count > 1 ? count : nil
    }

    /// The free slots on a weekday; an empty set means the athlete does not run that day.
    ///
    /// Assigning an empty set removes the weekday.
    public subscript(weekday: Weekday) -> Set<DaySlot> {
        get { slots[weekday] ?? [] }
        set { slots[weekday] = newValue.isEmpty ? nil : newValue }
    }

    private enum CodingKeys: String, CodingKey {
        case slots, slotOptions, runsPerDay
    }

    /// Decodes availability, ignoring weekdays and slots this version does not know (for instance
    /// written by a newer version) and treating a missing `slots` as no availability and a missing
    /// `slotOptions` as the default options on every slot. A missing `runsPerDay` means one run a
    /// day; entries of 1 or less, or for unknown weekdays, are dropped. The legacy `afternoonEvening`
    /// slot and options key stand for both ``DaySlot/afternoon`` and ``DaySlot/evening``; when
    /// options are stored under the legacy key and under a new name, the new name's options win.
    /// Saving it again writes only what was understood, in the new form, so the unknown values are
    /// lost.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decodeIfPresent([String: [String]].self, forKey: .slots) ?? [:]
        var decoded: [Weekday: Set<DaySlot>] = [:]
        for (key, names) in raw {
            guard let rawValue = Int(key), let weekday = Weekday(rawValue: rawValue) else { continue }
            let known = Set(names.flatMap(DaySlot.slots(forStoredName:)))
            if !known.isEmpty { decoded[weekday] = known }
        }
        slots = decoded

        let rawOptions = try container.decodeIfPresent([String: [String: SlotOptions]].self, forKey: .slotOptions) ?? [:]
        var decodedOptions: [Weekday: [DaySlot: SlotOptions]] = [:]
        for (key, perSlot) in rawOptions {
            guard let rawValue = Int(key), let weekday = Weekday(rawValue: rawValue) else { continue }
            // Legacy entries first so an entry stored under the new name wins over the one carried
            // from `afternoonEvening`.
            let ordered = perSlot.sorted { $0.key == DaySlot.legacyAfternoonEvening && $1.key != DaySlot.legacyAfternoonEvening }
            for (name, options) in ordered {
                for slot in DaySlot.slots(forStoredName: name) {
                    decodedOptions[weekday, default: [:]][slot] = options
                }
            }
        }
        slotOptions = Self.sparse(decodedOptions)

        let rawRuns = try container.decodeIfPresent([String: Int].self, forKey: .runsPerDay) ?? [:]
        var decodedRuns: [Weekday: Int] = [:]
        for (key, count) in rawRuns {
            guard let rawValue = Int(key), let weekday = Weekday(rawValue: rawValue), count > 1 else { continue }
            decodedRuns[weekday] = count
        }
        runsPerDay = decodedRuns
    }

    /// Encodes the slots keyed by the weekday's raw value (1 = Sunday), with slot names sorted so the
    /// output is stable, and the non-default slot options and the runs per day (above 1) keyed the
    /// same way.
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
        if !runsPerDay.isEmpty {
            try container.encode(Dictionary(uniqueKeysWithValues: runsPerDay.map { (String($0.key.rawValue), $0.value) }), forKey: .runsPerDay)
        }
    }
}
