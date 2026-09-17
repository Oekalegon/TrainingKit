/// The unit a ``WorkoutTemplateParameter``'s value is expressed in, for display and input
/// formatting in a template creator UI.
public enum ParameterUnit: Sendable, Codable, Hashable {
    case minutes
    case meters
    case count
}
