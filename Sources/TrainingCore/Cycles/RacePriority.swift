/// How much a race matters to the athlete, used to size its taper and to decide how strictly the
/// injury-risk/progress guardrails are checked against it.
///
/// ``KeyRaceLayout`` acts on it: the primary race anchors the macro, secondary races get a
/// mini-taper and recovery, tertiary races change nothing. ``CycleLayoutBuilder`` and
/// ``PlanEvaluator`` treat every race alike.
public enum RacePriority: Sendable, Codable, Hashable, CaseIterable {
    /// The goal race a macrocycle is built around; the layout tapers fully for it.
    case primary
    /// An important tune-up race; ``KeyRaceLayout`` gives it a shorter taper than a ``primary`` race and a recovery.
    case secondary
    /// A low-priority or training race; ``KeyRaceLayout`` races through it without taper or recovery.
    case tertiary
}
