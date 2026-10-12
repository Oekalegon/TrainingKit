import Foundation

/// A completed activity, imported or entered manually.
///
/// Heart-rate and speed samples are kept on the activity, not just the resulting
/// ``TrainingLoad``, so a recalculation with a changed `maxHeartRateBPM` or a different
/// ``LoadCalculator`` is possible without re-importing. Elevation, cadence, and the geographic
/// area covered are kept as one-time summaries rather than raw streams — see ``ElevationStats``,
/// ``CadenceStats``, and ``GeographicBounds`` for why.
public struct Activity: Identifiable, Sendable, Codable, Hashable {
    /// A stable identifier for this activity, independent of ``source``.
    public let id: UUID
    /// Where this activity came from, and the key used to dedupe re-imports.
    public var source: ActivitySource
    /// The kind of activity performed.
    public var sport: Sport
    /// When the activity began.
    public var start: Date
    /// How long the activity lasted.
    public var duration: TimeInterval
    /// Total distance covered, if the source/sport reports one.
    public var distanceMeters: Double?
    /// May be empty for sports/sources without heart-rate data; see ``DurationRPECalculator``.
    public var heartRate: [HeartRateSample]
    /// May be empty for sports/sources without speed data (e.g. indoor strength training).
    public var speed: [SpeedSample]
    /// Summarized elevation, if the source reports one; see ``ElevationStats``.
    public var elevation: ElevationStats?
    /// Summarized cadence, if the source reports one; see ``CadenceStats``.
    public var cadence: CadenceStats?
    /// The geographic area this activity took place within, if the source reports GPS data.
    public var geographicBounds: GeographicBounds?
    /// Borg CR10 rating of perceived exertion (1...10), used by ``DurationRPECalculator`` when
    /// no heart-rate data is available.
    public var perceivedExertion: Int?
    /// Set by ``PlanReconciler`` once this activity is matched to a ``PlannedActivity``.
    public var linkedPlanID: UUID?
    /// The ``PlannedActivity`` this workout was started from on the Apple Watch, if the source
    /// reports one (the id of the scheduled `WorkoutPlan`, which is the plan's own id).
    ///
    /// A hint, not a link: ``PlanReconciler`` turns it into ``linkedPlanID`` when that plan still
    /// exists, is unmatched and falls on the activity's day, and otherwise ignores it.
    public var scheduledPlanID: UUID?
    /// The steps of the plan this workout was started from, as the Watch recorded them (MVP2-146), in
    /// order; empty for a workout that wasn't started from a plan, for one imported before steps were
    /// read, and for a joined activity (its pieces' steps belong to different workouts). See
    /// ``ActivityStepAligner`` for laying them over the plan.
    public var steps: [ActivityStep]
    /// A training load carried in from outside (MVP2-107), in TRIMP: the figure a calendar export file
    /// gave for an activity whose heart rate the file doesn't hold. ``ImportedLoadCalculator`` uses it
    /// when there are no heart-rate samples to score. `nil` for every other activity.
    public var importedLoad: Double?
    /// Whether this activity was made from a calendar export file (MVP2-107), not read from its source:
    /// a placeholder with a start, a duration, a distance and a load but no heart rate, which the real
    /// workout replaces when HealthKit imports it. `false` for every other activity.
    public var isCalendarImport: Bool

    /// The time span this activity covers, from ``start`` to `start + duration`.
    ///
    /// Clamps a negative `duration` to zero rather than building an invalid `ClosedRange` (which
    /// would trap, since `ClosedRange` requires `lowerBound <= upperBound`) — malformed import
    /// data shouldn't be able to crash every caller that reads this.
    public var dateRange: ClosedRange<Date> {
        start...start.addingTimeInterval(max(duration, 0))
    }

    /// Creates a completed activity.
    ///
    /// - Parameters:
    ///   - id: A stable identifier; defaults to a new random `UUID`.
    ///   - source: Where this activity came from.
    ///   - sport: The kind of activity performed.
    ///   - start: When the activity began.
    ///   - duration: How long the activity lasted.
    ///   - distanceMeters: Total distance covered, if known.
    ///   - heartRate: Raw heart-rate samples, if any.
    ///   - speed: Raw speed samples, if any.
    ///   - elevation: Summarized elevation, if known.
    ///   - cadence: Summarized cadence, if known.
    ///   - geographicBounds: The geographic area covered, if known.
    ///   - perceivedExertion: Borg CR10 rating (1...10), if entered.
    ///   - linkedPlanID: The matched ``PlannedActivity``'s id, if already reconciled.
    ///   - scheduledPlanID: The id of the plan the workout was started from, if the source knows it.
    ///   - steps: The steps the Watch recorded for a plan-started workout; defaults to none.
    ///   - importedLoad: A load (TRIMP) carried in from a calendar export file; defaults to none.
    ///   - isCalendarImport: Whether the activity was made from a calendar export file; defaults to `false`.
    public init(
        id: UUID = UUID(),
        source: ActivitySource,
        sport: Sport,
        start: Date,
        duration: TimeInterval,
        distanceMeters: Double? = nil,
        heartRate: [HeartRateSample] = [],
        speed: [SpeedSample] = [],
        elevation: ElevationStats? = nil,
        cadence: CadenceStats? = nil,
        geographicBounds: GeographicBounds? = nil,
        perceivedExertion: Int? = nil,
        linkedPlanID: UUID? = nil,
        scheduledPlanID: UUID? = nil,
        steps: [ActivityStep] = [],
        importedLoad: Double? = nil,
        isCalendarImport: Bool = false
    ) {
        self.id = id
        self.source = source
        self.sport = sport
        self.start = start
        self.duration = duration
        self.distanceMeters = distanceMeters
        self.heartRate = heartRate
        self.speed = speed
        self.elevation = elevation
        self.cadence = cadence
        self.geographicBounds = geographicBounds
        self.perceivedExertion = perceivedExertion
        self.linkedPlanID = linkedPlanID
        self.scheduledPlanID = scheduledPlanID
        self.steps = steps
        self.importedLoad = importedLoad
        self.isCalendarImport = isCalendarImport
    }
}

extension Activity {
    private enum CodingKeys: String, CodingKey {
        case id, source, sport, start, duration, distanceMeters, heartRate, speed, elevation, cadence
        case geographicBounds, perceivedExertion, linkedPlanID, scheduledPlanID, steps, importedLoad, isCalendarImport
    }

    /// Decodes an activity, reading a missing `steps` as empty, and a missing imported load as none, so
    /// activities saved before those fields (MVP2-146, MVP2-107) still load.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        source = try container.decode(ActivitySource.self, forKey: .source)
        sport = try container.decode(Sport.self, forKey: .sport)
        start = try container.decode(Date.self, forKey: .start)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        distanceMeters = try container.decodeIfPresent(Double.self, forKey: .distanceMeters)
        heartRate = try container.decode([HeartRateSample].self, forKey: .heartRate)
        speed = try container.decode([SpeedSample].self, forKey: .speed)
        elevation = try container.decodeIfPresent(ElevationStats.self, forKey: .elevation)
        cadence = try container.decodeIfPresent(CadenceStats.self, forKey: .cadence)
        geographicBounds = try container.decodeIfPresent(GeographicBounds.self, forKey: .geographicBounds)
        perceivedExertion = try container.decodeIfPresent(Int.self, forKey: .perceivedExertion)
        linkedPlanID = try container.decodeIfPresent(UUID.self, forKey: .linkedPlanID)
        scheduledPlanID = try container.decodeIfPresent(UUID.self, forKey: .scheduledPlanID)
        steps = try container.decodeIfPresent([ActivityStep].self, forKey: .steps) ?? []
        importedLoad = try container.decodeIfPresent(Double.self, forKey: .importedLoad)
        isCalendarImport = try container.decodeIfPresent(Bool.self, forKey: .isCalendarImport) ?? false
    }
}
