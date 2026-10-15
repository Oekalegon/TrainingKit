import TrainingCore
import Foundation
import SwiftData

/// The persisted row for a custom `WorkoutTemplate` (MVP2-140). See ``ActivityRecord`` for why this is
/// a JSON payload plus one indexed lookup field rather than one attribute per model field, why the
/// class and `id` are public, and why `payload` isn't.
@Model
public final class WorkoutTemplateRecord {
    /// Mirrors `WorkoutTemplate.id`.
    public var id: UUID = UUID()
    /// The JSON-encoded `WorkoutTemplate`.
    var payload: Data = Data()

    init(id: UUID, payload: Data) {
        self.id = id
        self.payload = payload
    }
}

extension WorkoutTemplateRecord {
    /// Creates a template record by encoding `template`.
    ///
    /// - Parameter template: The template to persist.
    public convenience init(template: WorkoutTemplate) throws {
        self.init(id: template.id, payload: try PersistenceCoding.encode(template))
    }

    /// Decodes `payload` back into a `WorkoutTemplate`.
    public func toTemplate() throws -> WorkoutTemplate {
        try PersistenceCoding.decode(WorkoutTemplate.self, from: payload)
    }

    /// Replaces this record's `payload` with `template`'s, leaving `id` unchanged.
    ///
    /// - Parameter template: The template to update this record from.
    public func update(from template: WorkoutTemplate) throws {
        payload = try PersistenceCoding.encode(template)
    }
}
