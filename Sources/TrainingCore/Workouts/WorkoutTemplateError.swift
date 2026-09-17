/// An error resolving a ``WorkoutTemplate``'s parameters during
/// ``WorkoutTemplate/instantiate(name:values:)``.
public enum WorkoutTemplateError: Error, Sendable, Equatable {
    /// A `TemplateValue.parameter(_:)` referenced a key not declared in the template's
    /// `parameters` — a typo or a stale reference left behind by a rename, distinct from a
    /// declared parameter simply missing from the `values` passed to `instantiate(values:)` (which
    /// falls back to that parameter's `defaultValue` instead of failing).
    case undeclaredParameter(String)
}
