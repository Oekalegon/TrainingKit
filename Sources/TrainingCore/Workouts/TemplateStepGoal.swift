import Foundation

/// The template counterpart of ``StepGoal``: what ends a ``TemplateStep``, possibly left as a
/// named parameter instead of a fixed number.
public enum TemplateStepGoal: Sendable, Codable, Hashable {
    case time(TemplateValue<TimeInterval>)
    case distance(TemplateValue<Double>)
    case open
}
