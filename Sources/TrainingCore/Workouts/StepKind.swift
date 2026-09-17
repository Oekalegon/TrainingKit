/// The role a ``WorkoutStep`` plays within its ``WorkoutBlock``.
public enum StepKind: Sendable, Codable, Hashable {
    case warmup
    case work
    case recovery
    case cooldown
}
