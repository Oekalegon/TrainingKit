import Foundation

/// What the athlete wants from a generated plan: the generator's soft inputs.
///
/// Preferences are honoured where possible but never override ``PlanGuardrails``. For now this
/// carries ``runAvailability``, ``maxWeeklyVolume``, ``maxLongRunMeters`` and ``includeConditioning``; training days, starting volumes and ramp are
/// added by later tickets (design doc §8.1).
public struct PlanPreferences: Sendable, Codable, Hashable {
    /// When the athlete can run. Seeded from the athlete's global availability setting, which does
    /// not depend on any plan or on the training paradigm. Defaults to no availability.
    public var runAvailability: RunAvailability

    /// The most the athlete wants to train in any 7 days, per sport: the peak of the plan's weekly
    /// volume, whatever the length of a micro. Each value is in its own ``VolumeMeasure`` (distance,
    /// time or TRIMP), so a sport can be limited in a different measure than another.
    ///
    /// A sport without an entry has no limit beyond ``PlanGuardrails``; an empty dictionary (the
    /// default) means no limit at all. The value is a ceiling the generator aims to stay under, not a
    /// target to reach, and the volume curve (MVP5-117) reads it.
    public var maxWeeklyVolume: [Sport: VolumeTarget]

    /// The longest single run the athlete is willing to do, in meters, for a plan aimed at an
    /// ultra (``Race/isUltra``); `nil` (the default) when the athlete gave none, in which case the
    /// paradigm's ``TrainingParadigm/maxLongRunMeters`` applies. Finite and above zero; read it
    /// through ``maxLongRun(for:targetRace:)``. The generator (MVP5-117/118) reads it; no rule checks it yet.
    public var maxLongRunMeters: Double?

    /// Whether the athlete wants the paradigm's conditioning phase (``CyclePhase/conditioning``)
    /// before the base phase. `false` by default: conditioning is left out of the plan. When `true`
    /// it is included only while the lead time has room for it; ``LeadTimeCompromiser`` drops it
    /// otherwise and reports that the preference was overridden.
    public var includeConditioning: Bool

    /// The ceiling on a long run for a plan aimed at `targetRace`, in meters.
    ///
    /// Only an ultra target has one: `nil` for any other race, or none. For an ultra it is the
    /// athlete's ``maxLongRunMeters`` when set (even if higher than the paradigm's), otherwise the
    /// paradigm's ``TrainingParadigm/maxLongRunMeters``, which is `nil` for no ceiling.
    ///
    /// - Parameters:
    ///   - paradigm: The plan's paradigm, if any.
    ///   - targetRace: The race the plan builds towards, if any.
    public func maxLongRun(for paradigm: TrainingParadigm?, targetRace: Race?) -> Double? {
        guard targetRace?.isUltra == true else { return nil }
        return maxLongRunMeters ?? paradigm?.maxLongRunMeters
    }

    /// Creates plan preferences.
    ///
    /// - Parameters:
    ///   - runAvailability: When the athlete can run. Defaults to no availability.
    ///   - maxWeeklyVolume: The peak volume per 7 days for each sport. Defaults to no limit.
    ///   - maxLongRunMeters: The longest run the athlete will do, in meters, for an ultra target;
    ///     defaults to `nil` (the paradigm's ceiling applies). A value that is not finite or not
    ///     above zero is stored as `nil`.
    ///   - includeConditioning: Whether the athlete wants a conditioning phase; defaults to `false`.
    public init(
        runAvailability: RunAvailability = RunAvailability(),
        maxWeeklyVolume: [Sport: VolumeTarget] = [:],
        maxLongRunMeters: Double? = nil,
        includeConditioning: Bool = false
    ) {
        self.includeConditioning = includeConditioning
        self.maxLongRunMeters = maxLongRunMeters.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        self.runAvailability = runAvailability
        self.maxWeeklyVolume = maxWeeklyVolume
    }

    private enum CodingKeys: String, CodingKey {
        case runAvailability, maxWeeklyVolume, maxLongRunMeters, includeConditioning
    }

    /// One sport's limit, as stored: `Sport` encodes as an object, so a dictionary keyed by it
    /// would not be a JSON object.
    private struct VolumeLimit: Codable {
        let sport: Sport
        let volume: VolumeTarget
    }

    /// Decodes preferences, falling back to the default for any missing field so a payload written
    /// before a field existed still decodes. A `maxWeeklyVolume` that is not an array reads as no limit. A limit with an unknown sport or measure, or a
    /// non-positive or non-finite amount, is dropped; a repeated sport keeps its last entry.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        runAvailability = try container.decodeIfPresent(RunAvailability.self, forKey: .runAvailability) ?? RunAvailability()

        var limits: [Sport: VolumeTarget] = [:]
        if container.contains(.maxWeeklyVolume), var entries = try? container.nestedUnkeyedContainer(forKey: .maxWeeklyVolume) {
            while !entries.isAtEnd {
                if let limit = try? entries.decode(VolumeLimit.self) {
                    limits[limit.sport] = limit.volume
                } else {
                    _ = try? entries.decode(AnyDecodable.self)
                }
            }
        }
        maxWeeklyVolume = limits
        maxLongRunMeters = (try? container.decodeIfPresent(Double.self, forKey: .maxLongRunMeters)).flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        includeConditioning = (try? container.decodeIfPresent(Bool.self, forKey: .includeConditioning)) ?? false
    }

    /// Encodes the preferences; an empty ``maxWeeklyVolume``, a `nil` ``maxLongRunMeters`` and a `false` ``includeConditioning`` are left out.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(runAvailability, forKey: .runAvailability)
        try container.encodeIfPresent(maxLongRunMeters, forKey: .maxLongRunMeters)
        if includeConditioning { try container.encode(true, forKey: .includeConditioning) }
        if !maxWeeklyVolume.isEmpty {
            let sorter = JSONEncoder()
            sorter.outputFormatting = JSONEncoder.OutputFormatting.sortedKeys
            let entries = try maxWeeklyVolume
                .map { (key: try sorter.encode($0.key), limit: VolumeLimit(sport: $0.key, volume: $0.value)) }
                .sorted { $0.key.lexicographicallyPrecedes($1.key) }
                .map(\.limit)
            try container.encode(entries, forKey: .maxWeeklyVolume)
        }
    }

    /// Skips an array element that failed to decode.
    private struct AnyDecodable: Decodable {
        init(from decoder: Decoder) throws {}
    }
}
