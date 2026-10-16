/// What the athlete wants from a generated plan: the generator's soft inputs.
///
/// Preferences are honoured where possible but never override ``PlanGuardrails``. For now this
/// carries ``runAvailability`` and the run types per micro day (``dayRunTypes``); training days,
/// volumes and ramp are added by later tickets (design doc §8.1).
///
/// ## Run types per micro day
///
/// ``dayRunTypes`` is keyed by the 0-based day within a micro-cycle (day 0 is its first day), so
/// the valid keys are `0..<microLength` and depend on the micro length (7, 10 or 14 days, the
/// athlete's choice). The length is not part of the preferences, so out-of-range keys are not
/// rejected on storage: they are kept (so changing the micro length back restores them), ignored
/// by ``runTypes(onDay:microLength:)`` and removed by ``validated(microLength:)``. Only negative
/// keys can never be valid and are dropped on init, on decode and on ``setRunTypes(_:onDay:)``.
public struct PlanPreferences: Sendable, Codable, Hashable {
    /// When the athlete can run. Seeded from the athlete's global availability setting, which does
    /// not depend on any plan or on the training paradigm. Defaults to no availability.
    public var runAvailability: RunAvailability

    /// The run types the athlete allows on each micro day, keyed by the 0-based day within the
    /// micro-cycle. A day never maps to an empty set: empty entries are removed. A day without an
    /// entry allows only ``RunType/defaultForUnspecifiedDay``; read the effective types through
    /// ``runTypes(onDay:microLength:)``.
    public private(set) var dayRunTypes: [Int: Set<RunType>]

    /// Creates plan preferences.
    ///
    /// - Parameters:
    ///   - runAvailability: When the athlete can run. Defaults to no availability.
    ///   - dayRunTypes: The allowed run types per 0-based micro day. Empty sets and negative days
    ///     are dropped. Defaults to none, so every day allows ``RunType/defaultForUnspecifiedDay``.
    public init(
        runAvailability: RunAvailability = RunAvailability(),
        dayRunTypes: [Int: Set<RunType>] = [:]
    ) {
        self.runAvailability = runAvailability
        self.dayRunTypes = dayRunTypes.filter { $0.key >= 0 && !$0.value.isEmpty }
    }

    /// The run types allowed on a day of a micro-cycle of the given length.
    ///
    /// - Parameters:
    ///   - day: The 0-based day within the micro.
    ///   - microLength: The micro's length in days.
    /// - Returns: An empty set when `day` is outside `0..<microLength` (the day does not exist in
    ///   that micro); the stored types when there are some; otherwise
    ///   ``RunType/defaultForUnspecifiedDay``.
    public func runTypes(onDay day: Int, microLength: Int) -> Set<RunType> {
        guard day >= 0, day < microLength else { return [] }
        return dayRunTypes[day] ?? RunType.defaultForUnspecifiedDay
    }

    /// Sets the run types allowed on a micro day.
    ///
    /// The day is stored even when it is beyond the current micro length (see the type
    /// documentation). An empty set removes the entry, so the day allows
    /// ``RunType/defaultForUnspecifiedDay`` again; a negative day is ignored.
    ///
    /// - Parameters:
    ///   - types: The allowed run types.
    ///   - day: The 0-based day within the micro.
    public mutating func setRunTypes(_ types: Set<RunType>, onDay day: Int) {
        guard day >= 0 else { return }
        dayRunTypes[day] = types.isEmpty ? nil : types
    }

    /// A copy without the run-type entries that do not fit a micro of the given length.
    ///
    /// - Parameter microLength: The micro's length in days.
    /// - Returns: These preferences with only the ``dayRunTypes`` days in `0..<microLength` kept.
    public func validated(microLength: Int) -> PlanPreferences {
        var copy = self
        copy.dayRunTypes = dayRunTypes.filter { $0.key < microLength }
        return copy
    }

    private enum CodingKeys: String, CodingKey {
        case runAvailability, dayRunTypes
    }

    /// Decodes preferences, falling back to the default for any missing field so a payload written
    /// before a field existed still decodes. Run types this version does not know, and days that
    /// are not integers or are negative, are dropped;. Saving again writes only what was understood.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        runAvailability = try container.decodeIfPresent(RunAvailability.self, forKey: .runAvailability) ?? RunAvailability()

        let raw = try container.decodeIfPresent([String: [String]].self, forKey: .dayRunTypes) ?? [:]
        var decoded: [Int: Set<RunType>] = [:]
        for (key, names) in raw {
            guard let day = Int(key), day >= 0 else { continue }
            let known = Set(names.compactMap(RunType.init(rawValue:)))
            if !known.isEmpty { decoded[day] = known }
        }
        dayRunTypes = decoded
    }

    /// Encodes the run types keyed by the day as a string, with type names sorted so the output is
    /// stable. Run types are written only when set.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(runAvailability, forKey: .runAvailability)
        if !dayRunTypes.isEmpty {
            let raw = Dictionary(uniqueKeysWithValues: dayRunTypes.map { (String($0.key), $0.value.map(\.rawValue).sorted()) })
            try container.encode(raw, forKey: .dayRunTypes)
        }
    }
}
