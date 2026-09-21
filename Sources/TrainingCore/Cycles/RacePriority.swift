/// How much a race matters to the athlete, used to size its taper and to decide how strictly the
/// injury-risk/progress guardrails are checked against it.
///
/// This is model-only in MVP 2: nothing yet varies behaviour by priority (the layout and
/// ``PlanEvaluator`` treat every race alike). MVP 5's plan builder is what acts on it.
public enum RacePriority: Sendable, Codable, Hashable, CaseIterable {
    /// The goal race a macrocycle is built around; the layout tapers fully for it.
    case primary
    /// An important tune-up race, worth a shorter taper than a ``primary`` race.
    case secondary
    /// A low-priority or training race, raced through rather than tapered for.
    case tertiary
}
