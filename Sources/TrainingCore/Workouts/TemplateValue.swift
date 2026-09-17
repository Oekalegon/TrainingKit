/// Either a fixed value or a reference to a named ``WorkoutTemplate`` parameter, resolved when
/// the template is instantiated into a concrete ``StructuredWorkout``.
public enum TemplateValue<Value: Sendable & Codable & Hashable>: Sendable, Codable, Hashable {
    case fixed(Value)
    case parameter(String)
}
