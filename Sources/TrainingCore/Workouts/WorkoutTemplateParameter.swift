/// A named input a ``WorkoutTemplate`` exposes, e.g. "Duration" in minutes.
public struct WorkoutTemplateParameter: Identifiable, Sendable, Codable, Hashable {
    /// The key `TemplateValue.parameter(_:)` references within the owning template's blocks.
    public var key: String
    /// The display name, e.g. "Duration".
    public var name: String
    /// The unit this parameter's value is expressed in.
    public var unit: ParameterUnit
    /// The value used when instantiating the template without an explicit override.
    public var defaultValue: Double
    /// Bounds for a creator UI's slider/stepper, if any.
    public var range: ClosedRange<Double>?

    /// The parameter's own key, used as its stable identity.
    public var id: String { key }

    /// Creates a template parameter.
    ///
    /// - Parameters:
    ///   - key: The key `TemplateValue.parameter(_:)` references within the owning template's blocks.
    ///   - name: The display name, e.g. "Duration".
    ///   - unit: The unit this parameter's value is expressed in.
    ///   - defaultValue: The value used when instantiating the template without an explicit override.
    ///   - range: Bounds for a creator UI's slider/stepper, if any.
    public init(
        key: String,
        name: String,
        unit: ParameterUnit,
        defaultValue: Double,
        range: ClosedRange<Double>? = nil
    ) {
        self.key = key
        self.name = name
        self.unit = unit
        self.defaultValue = defaultValue
        self.range = range
    }
}
