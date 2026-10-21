import Foundation

/// The result of ``TemplateFitter/fit(profile:targetSeconds:templates:previous:workLength:athlete:)``.
public enum TemplateFit: Sendable, Hashable {
    /// A template passed the filter; this is the closest fit, after rotation.
    case fit(TemplateChoice)
    /// No template can meet the profile. The generator reports it as a compromise (MVP5-120).
    case missingTemplate(SessionProfile)
}
