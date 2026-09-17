/// How much a race matters, used to size its taper and — in MVP 1's `PlanEvaluator` (not yet
/// built) — the injury-risk/progress guardrails checked against it.
public enum RacePriority: Sendable, Codable, Hashable, CaseIterable {
    /// The primary goal race a macrocycle is built around; the layout tapers fully for it.
    case a
    /// An important tune-up race; MVP 1 treats it like an A race for layout purposes, but this
    /// distinction exists for MVP 2's differentiated taper/guardrail handling.
    case b
    /// A low-priority or training race, raced through rather than tapered for; not yet
    /// differentiated from `.a`/`.b` until MVP 2.
    case c
}
