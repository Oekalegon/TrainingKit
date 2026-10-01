import Foundation

/// A day-by-day export of an athlete's training calendar over a chosen period (MVP2-100), for
/// analysis outside the app, e.g. a season plan in a spreadsheet or another tool.
///
/// Each ``Day`` lists every completed activity and every still-to-do planned workout on it, plus
/// that day's fitness metrics. Missed plans (before today, never performed) are left out: they
/// never became training load. A plan that was performed appears once, inside its completed
/// activity's ``Entry/plan``, rather than as a second entry.
///
/// Built by ``TrainingModel/calendarExport(from:through:templates:asOf:)``. Encode it with
/// ``jsonData()`` so dates, day strings and number handling match the documented format.
public struct CalendarExport: Sendable, Codable, Hashable {
    /// The format version, bumped when a field is renamed or removed (adding fields doesn't).
    public static let currentSchemaVersion = 1

    /// The format version this export was written with.
    public let schemaVersion: Int
    /// When the export was made.
    public let generatedAt: Date
    /// The athlete's time zone identifier, e.g. `Europe/Amsterdam`. Every ``Day/date`` is a
    /// calendar day in this zone.
    public let timeZone: String
    /// The first day of the period, as `yyyy-MM-dd`.
    public let firstDay: String
    /// The last day of the period, as `yyyy-MM-dd`, inclusive.
    public let lastDay: String
    /// One entry per calendar day from ``firstDay`` through ``lastDay``, in order, including days
    /// with no activities.
    public let days: [Day]

    /// One calendar day.
    public struct Day: Sendable, Codable, Hashable {
        /// The day, as `yyyy-MM-dd` in ``CalendarExport/timeZone``.
        public let date: String
        /// The day's fitness metrics, or `nil` when the series doesn't reach this day (no
        /// activities or plans on or before it).
        public let metrics: Metrics?
        /// The day's completed activities, then its planned workouts, each in time order.
        public let activities: [Entry]
    }

    /// A day's fitness metrics (see ``FitnessMetrics``).
    public struct Metrics: Sendable, Codable, Hashable {
        /// The day's total load, in TRIMP. Actual load up to today, expected load after.
        public let load: Double
        /// Chronic training load ("fitness").
        public let ctl: Double
        /// Acute training load ("fatigue").
        public let atl: Double
        /// Training stress balance ("form"): yesterday's CTL minus yesterday's ATL.
        public let tsb: Double
        /// Training monotony over the trailing window, or `nil` when it's undefined (a perfectly
        /// flat window, such as a week of rest).
        public let monotony: Double?
        /// Training strain over the trailing window, or `nil` when monotony is undefined.
        public let strain: Double?
        /// `true` when the day's load includes an estimate (a planned workout).
        public let isProjected: Bool
        /// `true` while CTL and ATL are still ramping up from too little history.
        public let isWarmingUp: Bool
    }

    /// A completed activity or a planned workout.
    public struct Entry: Sendable, Codable, Hashable {
        /// Whether the entry was performed or is still to do.
        public enum Status: String, Sendable, Codable, Hashable {
            /// A recorded activity.
            case completed
            /// A planned workout for today or later that hasn't been performed yet.
            case planned
        }

        /// Where ``Entry/trimp`` came from.
        public enum TRIMPSource: String, Sendable, Codable, Hashable {
            /// Computed from the activity's heart rate.
            case heartRate
            /// Estimated from duration and perceived exertion (no heart rate).
            case perceivedExertion
            /// Estimated from the planned workout's steps.
            case estimated
            /// The plan's own expected-load override.
            case override
        }

        /// Whether this was performed or is still planned.
        public let status: Status
        /// When a completed activity started. `nil` for a planned workout, which has a day but no
        /// time.
        public let start: Date?
        /// The workout's name: the planned workout's, or for a completed activity the name of the
        /// plan it fulfilled. `nil` for a completed activity with no linked plan, since recorded
        /// activities have no name of their own.
        public let name: String?
        /// The sport, e.g. `running`, `cycling`, `coreStrengthTraining`; an unrecognised sport is
        /// its own label.
        public let sport: String
        /// The workout template the planned workout was built from, e.g. `Tempo Run`, if known.
        public let template: String?
        /// The intensity category: `veryLow`, `low`, `medium` or `high`. What was performed for a
        /// completed activity, what's intended for a planned one.
        public let intensity: String?
        /// Training load in TRIMP: actual for a completed activity, expected for a planned one.
        /// `nil` when it couldn't be computed.
        public let trimp: Double?
        /// Where ``trimp`` came from.
        public let trimpSource: TRIMPSource?
        /// Duration in seconds: recorded, or expected for a planned workout.
        public let durationSeconds: Double
        /// Distance in meters: recorded, or expected for a planned workout. `nil` when unknown,
        /// e.g. a strength session, or a duration-based plan for an athlete without zone settings.
        public let distanceMeters: Double?
        /// For a completed activity that fulfilled a plan, what that plan expected.
        public let plan: PlannedValues?
    }

    /// What a plan expected, attached to the completed activity that fulfilled it.
    public struct PlannedValues: Sendable, Codable, Hashable {
        /// The planned workout's name.
        public let name: String
        /// The template it was built from, if known.
        public let template: String?
        /// The expected load, in TRIMP.
        public let trimp: Double
        /// Whether ``trimp`` is the plan's override or an estimate.
        public let trimpSource: Entry.TRIMPSource
        /// The expected duration, in seconds.
        public let durationSeconds: Double
        /// The expected distance, in meters, if it can be projected.
        public let distanceMeters: Double?
    }

    /// The export as pretty-printed JSON with sorted keys and ISO 8601 dates.
    ///
    /// `nil` values are written as `null` rather than left out, so every day and entry has the
    /// same keys.
    ///
    /// - Returns: UTF-8 JSON.
    /// - Throws: `EncodingError` if encoding fails (it shouldn't: non-finite numbers are already
    ///   `nil`).
    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}

// Explicit encoders: the synthesized ones skip `nil` values, but the format promises `null`, so
// every day and entry carries the same keys for tools that expect a fixed shape.

extension CalendarExport.Day {
    private enum CodingKeys: String, CodingKey { case date, metrics, activities }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(date, forKey: .date)
        try container.encode(metrics, forKey: .metrics)
        try container.encode(activities, forKey: .activities)
    }
}

extension CalendarExport.Metrics {
    private enum CodingKeys: String, CodingKey {
        case load, ctl, atl, tsb, monotony, strain, isProjected, isWarmingUp
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(load, forKey: .load)
        try container.encode(ctl, forKey: .ctl)
        try container.encode(atl, forKey: .atl)
        try container.encode(tsb, forKey: .tsb)
        try container.encode(monotony, forKey: .monotony)
        try container.encode(strain, forKey: .strain)
        try container.encode(isProjected, forKey: .isProjected)
        try container.encode(isWarmingUp, forKey: .isWarmingUp)
    }
}

extension CalendarExport.Entry {
    private enum CodingKeys: String, CodingKey {
        case status, start, name, sport, template, intensity, trimp, trimpSource
        case durationSeconds, distanceMeters, plan
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status, forKey: .status)
        try container.encode(start, forKey: .start)
        try container.encode(name, forKey: .name)
        try container.encode(sport, forKey: .sport)
        try container.encode(template, forKey: .template)
        try container.encode(intensity, forKey: .intensity)
        try container.encode(trimp, forKey: .trimp)
        try container.encode(trimpSource, forKey: .trimpSource)
        try container.encode(durationSeconds, forKey: .durationSeconds)
        try container.encode(distanceMeters, forKey: .distanceMeters)
        try container.encode(plan, forKey: .plan)
    }
}

extension CalendarExport.PlannedValues {
    private enum CodingKeys: String, CodingKey {
        case name, template, trimp, trimpSource, durationSeconds, distanceMeters
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(template, forKey: .template)
        try container.encode(trimp, forKey: .trimp)
        try container.encode(trimpSource, forKey: .trimpSource)
        try container.encode(durationSeconds, forKey: .durationSeconds)
        try container.encode(distanceMeters, forKey: .distanceMeters)
    }
}
