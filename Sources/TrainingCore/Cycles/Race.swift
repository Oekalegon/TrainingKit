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
    /// The training load the race adds on its day, or `nil` to let ``DailyLoadSeries`` estimate it
    /// from the distance and the ``specificPhaseTarget``. Zero or more, and finite (see ``validate()``).
    ///
    /// Set it when the estimate is off, the way ``PlannedActivity/expectedLoadOverride`` does for a
    /// planned run, or when the athlete has no heart-rate zone settings (the estimator then gives 0).
    /// A race that has been run counts through its activity instead.
    public var expectedLoadOverride: Double?

    /// Creates a race.
    ///
    /// - Parameters:
    ///   - id: A stable identifier; defaults to a new random `UUID`.
    ///   - name: The race's display name.
    ///   - date: The calendar day the race takes place, in the athlete's timezone.
    ///   - priority: How much this race matters to the athlete; see ``KeyRaceLayout``.
    ///   - distanceMeters: The distance of the race, in meters; must pass ``validate()``.
    ///   - specificPhaseTarget: The intensity the specific-phase work is aimed at; defaults to `nil`, none.
    ///   - expectedLoadOverride: The load the race adds on its day; defaults to `nil`, estimated.
    public init(
        id: UUID = UUID(), name: String, date: Date, priority: RacePriority,
        distanceMeters: Double, specificPhaseTarget: SpecificPhaseTarget? = nil, expectedLoadOverride: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.date = date
        self.priority = priority
        self.distanceMeters = distanceMeters
        self.specificPhaseTarget = specificPhaseTarget
        self.expectedLoadOverride = expectedLoadOverride
    }

    /// The marathon distance in meters; a race longer than this is an ultra.
    public static let marathonDistanceMeters = 42_195.0

    /// Whether the race is longer than a marathon (``marathonDistanceMeters``), which makes the
    /// plan an ultra plan: see ``TrainingParadigm/resolved(for:)``.
    public var isUltra: Bool { distanceMeters > Self.marathonDistanceMeters }

    /// Checks that the race makes sense.
    ///
    /// - Throws: ``RaceError/invalidDistance`` if ``distanceMeters`` is not finite or not above zero,
    ///   ``RaceError/invalidExpectedLoad`` if ``expectedLoadOverride`` is set and is not finite or is negative.
    public func validate() throws {
        guard distanceMeters.isFinite, distanceMeters > 0 else { throw RaceError.invalidDistance }
        if let expectedLoadOverride {
            guard expectedLoadOverride.isFinite, expectedLoadOverride >= 0 else { throw RaceError.invalidExpectedLoad }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, date, priority, distanceMeters, specificPhaseTarget, expectedLoadOverride
    }

    /// Decodes a race and validates it. A race with no distance, or an invalid one, does not decode:
    /// the stores skip and log it.
    ///
    /// See ``specificPhaseTarget`` for how a missing, unknown or invalid target decodes. A stored race
    /// without an ``expectedLoadOverride``, or with one that is negative or not finite, decodes it as
    /// `nil`, so a bad value never loses the race.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        date = try container.decode(Date.self, forKey: .date)
        priority = try container.decode(RacePriority.self, forKey: .priority)
        distanceMeters = try container.decode(Double.self, forKey: .distanceMeters)
        specificPhaseTarget = try? container.decodeIfPresent(SpecificPhaseTarget.self, forKey: .specificPhaseTarget)
        expectedLoadOverride = (try? container.decodeIfPresent(Double.self, forKey: .expectedLoadOverride))
            .flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        try validate()
    }
}
