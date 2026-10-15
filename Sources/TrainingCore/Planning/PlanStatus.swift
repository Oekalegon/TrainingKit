/// Where a ``TrainingPlan`` stands: being worked on, in use, or finished.
public enum PlanStatus: String, Sendable, Codable, Hashable, CaseIterable {
    /// Not in use. Its planned workouts and cycles stay editable, and can be previewed or evaluated,
    /// but don't feed the fitness series, statistics, activity matching or calendar export.
    case draft
    /// The plan in use. At most one plan has this status.
    case active
    /// Finished or put away. Treated like a ``draft`` for what feeds the series.
    case archived
    /// Stopped part-way, on ``TrainingPlan/cancelledDate``, typically because a new plan replaced it.
    /// The plan and what was done under it stay as history; like ``archived``, it feeds nothing.
    case cancelled

    /// Decodes a status, reading one this version doesn't know (written by a newer version on another
    /// device) as ``draft``, so the plan stays readable and inactive rather than failing to decode
    /// and leaving its workouts counting.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PlanStatus(rawValue: raw) ?? .draft
    }
}
