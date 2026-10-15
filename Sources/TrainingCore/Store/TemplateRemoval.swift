/// What ``TrainingModel/deleteTemplate(id:asOf:)`` did to a template.
public enum TemplateRemoval: Sendable, Equatable {
    /// No plan used the template, so it was removed.
    case deleted
    /// A plan still uses the template, so it was kept with ``WorkoutTemplate/archivedDate`` set.
    case archived
}
