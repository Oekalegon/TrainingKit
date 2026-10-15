/// The template counterpart of ``WorkoutBlock``. `repetitions` may itself be a parameter, e.g.
/// "N x 400m" where N varies by plan week.
public struct TemplateBlock: Sendable, Codable, Hashable {
    /// The steps making up one repetition of this block.
    public var steps: [TemplateStep]
    /// How many times `steps` repeats.
    public var repetitions: TemplateValue<Int>

    /// Creates a template block.
    ///
    /// - Parameters:
    ///   - steps: The steps making up one repetition of this block.
    ///   - repetitions: How many times `steps` repeats; defaults to a fixed `1`.
    public init(steps: [TemplateStep], repetitions: TemplateValue<Int> = .fixed(1)) {
        self.steps = steps
        self.repetitions = repetitions
    }
}
