import Foundation

/// Storage contract for the athlete's library of workout templates.
public protocol WorkoutTemplateStore: Sendable {
    /// Every template in the library.
    func templates() async throws -> [WorkoutTemplate]

    /// The template with this id, if any.
    func template(id: UUID) async throws -> WorkoutTemplate?

    /// Inserts new templates or replaces existing ones matched by `id`.
    func upsert(_ templates: [WorkoutTemplate]) async throws

    /// Removes the template with this id, if any.
    func deleteTemplate(id: UUID) async throws
}
