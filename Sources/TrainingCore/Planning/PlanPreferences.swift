/// What the athlete wants from a generated plan: the generator's soft inputs.
///
/// Preferences are honoured where possible but never override ``PlanGuardrails``. For now this
/// carries ``runAvailability`` and ``maxWeeklyVolume``; training days, starting volumes and ramp are
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

    /// Creates plan preferences.
    ///
    /// - Parameters:
    ///   - runAvailability: When the athlete can run. Defaults to no availability.
    ///   - maxWeeklyVolume: The peak volume per 7 days for each sport. Defaults to no limit.
    public init(
        runAvailability: RunAvailability = RunAvailability(),
        maxWeeklyVolume: [Sport: VolumeTarget] = [:]
    ) {
        self.runAvailability = runAvailability
        self.maxWeeklyVolume = maxWeeklyVolume
    }

    private enum CodingKeys: String, CodingKey {
        case runAvailability, maxWeeklyVolume
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
    }

    /// Encodes the preferences; an empty ``maxWeeklyVolume`` is left out.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(runAvailability, forKey: .runAvailability)
        if !maxWeeklyVolume.isEmpty {
            let entries = maxWeeklyVolume
                .map { VolumeLimit(sport: $0.key, volume: $0.value) }
                .sorted { "\($0.sport)" < "\($1.sport)" }
            try container.encode(entries, forKey: .maxWeeklyVolume)
        }
    }

    /// Skips an array element that failed to decode.
    private struct AnyDecodable: Decodable {
        init(from decoder: Decoder) throws {}
    }
}
