/// Where a ``TrainingPlan`` stands: being worked on, in use, or finished.
public enum PlanStatus: String, Sendable, Codable, Hashable, CaseIterable {
    /// Not in use. Its planned workouts and cycles stay editable, and can be previewed or evaluated,
    /// but don't feed the fitness series, statistics, activity matching or calendar export.
    case draft
    /// The plan in use. At most one plan has this status.
    case active
    /// Finished or put away. Treated like a ``draft`` for what feeds the series.
    case archived
}
