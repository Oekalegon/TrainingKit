import Foundation

/// The template and parameter values ``TemplateFitter`` chose for a ``SessionProfile``.
public struct TemplateChoice: Sendable, Hashable {
    /// The chosen template.
    public let template: WorkoutTemplate
    /// The parameter values to instantiate it with, one per parameter (see
    /// ``WorkoutTemplate/instantiate(name:venue:values:)``).
    public let values: [String: Double]
    /// The estimated duration of the session with `values`, in seconds.
    public let seconds: TimeInterval
    /// How far `seconds` is from the target, as a fraction of the target (0.1 is 10 % off).
    public let error: Double
    /// What the template contains.
    public let analysis: TemplateAnalysis

    /// Creates a choice.
    ///
    /// - Parameters:
    ///   - template: The chosen template.
    ///   - values: The parameter values to instantiate it with.
    ///   - seconds: The estimated duration with `values`, in seconds.
    ///   - error: The relative distance of `seconds` from the target.
    ///   - analysis: What the template contains.
    public init(template: WorkoutTemplate, values: [String: Double], seconds: TimeInterval, error: Double, analysis: TemplateAnalysis) {
        self.template = template
        self.values = values
        self.seconds = seconds
        self.error = error
        self.analysis = analysis
    }
}
