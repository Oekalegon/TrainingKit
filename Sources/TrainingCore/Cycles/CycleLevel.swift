/// The nesting level of a ``TrainingCycle``: a macro contains mesos, a meso contains micros.
public enum CycleLevel: Sendable, Codable, Hashable {
    case macro
    case meso
    case micro
}
