import TrainingCore
import Foundation
import SwiftData

/// The persisted row for a library `StructuredWorkout`. See ``ActivityRecord`` for why this is a
/// JSON payload plus one indexed lookup field rather than one attribute per model field, why the
/// class and `id` are public, and why `payload` isn't.
@Model
public final class StructuredWorkoutRecord {
    /// Mirrors `StructuredWorkout.id`.
    public var id: UUID = UUID()
    /// The JSON-encoded `StructuredWorkout`.
    var payload: Data = Data()

    init(id: UUID, payload: Data) {
        self.id = id
        self.payload = payload
    }
}

extension StructuredWorkoutRecord {
    /// Creates a structured-workout record by encoding `workout`.
    ///
    /// - Parameter workout: The workout to persist.
    public convenience init(workout: StructuredWorkout) throws {
        self.init(id: workout.id, payload: try PersistenceCoding.encode(workout))
    }

    /// Decodes `payload` back into a `StructuredWorkout`.
    public func toWorkout() throws -> StructuredWorkout {
        try PersistenceCoding.decode(StructuredWorkout.self, from: payload)
    }

    /// Replaces this record's `payload` with `workout`'s, leaving `id` unchanged.
    ///
    /// - Parameter workout: The workout to update this record from.
    public func update(from workout: StructuredWorkout) throws {
        payload = try PersistenceCoding.encode(workout)
    }
}
