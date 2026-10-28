import Foundation

/// How many days a workout wants free of other demanding workouts before and after it (MVP5-147).
///
/// Days are counted like ``TrainingParadigm/minDaysBetweenHardSessions``: a workout on Tuesday and
/// the next on Thursday are 2 days apart, with one easy day between. For two demanding workouts, an
/// earlier `A` and a later `B`, the days between their dates must be at least `A.after + B.before`.
/// So an intense workout with `before` 0 and `after` 2 can be followed by another two days later, and
/// a workout that wants 1 day before it needs 3 days after an ordinary intense one.
///
/// A workout that wants nothing on either side (0 and 0), like an easy or a recovery run, is not
/// demanding: it neither needs recovery nor blocks the days next to it. The numbers are minimums to
/// aim for, not absolutes; the plan generator keeps a workout that cannot meet them and reports it
/// (``PlanCompromise/recoveryDaysShort(day:template:neededDays:availableDays:)``).
public struct RecoveryDays: Sendable, Codable, Hashable {
    /// The days wanted free of demanding workouts before the workout; at least 0.
    public var before: Int
    /// The days wanted free of demanding workouts after the workout; at least 0.
    public var after: Int

    /// Creates the days wanted around a workout.
    ///
    /// - Parameters:
    ///   - before: The days wanted before the workout; a negative value is raised to 0.
    ///   - after: The days wanted after the workout; a negative value is raised to 0.
    public init(before: Int, after: Int) {
        self.before = max(before, 0)
        self.after = max(after, 0)
    }

    /// Whether the workout wants nothing on either side.
    public var isNone: Bool { before == 0 && after == 0 }

    private enum CodingKeys: String, CodingKey { case before, after }

    /// Decodes the days; a missing or negative number reads as 0.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            before: (try? container.decodeIfPresent(Int.self, forKey: .before)) ?? 0,
            after: (try? container.decodeIfPresent(Int.self, forKey: .after)) ?? 0
        )
    }
}
