import Foundation

/// A target race a training cycle is built around.
///
/// A dated event over a distance, with a ``RacePriority``. It anchors a ``CycleLayoutBuilder``
/// layout and the race-day TSB rule in ``PlanEvaluator``; a non-event target with no date is a
/// separate ``Goal``. A personal target such as "run 50 km on this day" is also a `Race`, only not an
/// organised one; the distance says whether it is an ultra (``isUltra``).
public struct Race: Identifiable, Sendable, Codable, Hashable {
    /// A stable identifier for this race.
    public let id: UUID
    /// The race's display name.
    public var name: String
    /// The calendar day the race takes place, in the athlete's timezone.
    public var date: Date
    /// How much this race matters to the athlete; see ``KeyRaceLayout``.
    public var priority: RacePriority
    /// The distance of the race, in meters; finite and above zero (see ``validate()``).
    public var distanceMeters: Double
    /// The intensity the race's specific-phase work is aimed at, or `nil` for none (MVP5-114).
    ///
    /// Only ``StepTargetResolver`` reads it so far (MVP5-122). A stored race without the field decodes to `nil`, and so does one whose
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
    ///   - distanceMeters: The distance of the race, in meters; must pass ``validate()``.
    ///   - specificPhaseTarget: The intensity the specific-phase work is aimed at; defaults to `nil`, none.
    public init(
        id: UUID = UUID(), name: String, date: Date, priority: RacePriority,
        distanceMeters: Double, specificPhaseTarget: SpecificPhaseTarget? = nil
    ) {
        self.id = id
        self.name = name
        self.date = date
        self.priority = priority
        self.distanceMeters = distanceMeters
        self.specificPhaseTarget = specificPhaseTarget
    }

    /// The marathon distance in meters; a race longer than this is an ultra.
    public static let marathonDistanceMeters = 42_195.0

    /// Whether the race is longer than a marathon (``marathonDistanceMeters``), which makes the
    /// plan an ultra plan: see ``TrainingParadigm/resolved(for:)``.
    public var isUltra: Bool { distanceMeters > Self.marathonDistanceMeters }

    /// Checks that the race makes sense.
    ///
    /// - Throws: ``RaceError/invalidDistance`` if ``distanceMeters`` is not finite or not above zero.
    public func validate() throws {
        guard distanceMeters.isFinite, distanceMeters > 0 else { throw RaceError.invalidDistance }
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, date, priority, distanceMeters, specificPhaseTarget
    }

    /// Decodes a race and validates it. A race with no distance, or an invalid one, does not decode:
    /// the stores skip and log it.
    ///
    /// See ``specificPhaseTarget`` for how a missing, unknown or invalid target decodes.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        date = try container.decode(Date.self, forKey: .date)
        priority = try container.decode(RacePriority.self, forKey: .priority)
        distanceMeters = try container.decode(Double.self, forKey: .distanceMeters)
        specificPhaseTarget = try? container.decodeIfPresent(SpecificPhaseTarget.self, forKey: .specificPhaseTarget)
        try validate()
    }
}
