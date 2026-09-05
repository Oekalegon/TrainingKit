/// The training emphasis of a ``TrainingCycle``.
public enum CyclePhase: Sendable, Codable, Hashable {
    case base
    case build
    case peak
    case taper
    case race
    case recovery
    case transition
}
