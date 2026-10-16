import TrainingCore
import Foundation
import SwiftData

/// The persisted row for a `TrainingPlan`. See ``ActivityRecord`` for why this is a JSON payload plus one
/// indexed lookup field rather than one attribute per model field, why the class and `id` are
/// public, and why `payload` isn't.
@Model
public final class TrainingPlanRecord {
    /// Mirrors `TrainingPlan.id`.
    public var id: UUID = UUID()
    /// The JSON-encoded `TrainingPlan`.
    var payload: Data = Data()

    init(id: UUID, payload: Data) {
        self.id = id
        self.payload = payload
    }
}

extension TrainingPlanRecord {
    /// Creates a training-plan record by encoding `plan`.
    ///
    /// - Parameter plan: The plan to persist.
    public convenience init(plan: TrainingPlan) throws {
        self.init(id: plan.id, payload: try PersistenceCoding.encode(plan))
    }

    /// Decodes `payload` back into a `TrainingPlan`.
    public func toTrainingPlan() throws -> TrainingPlan {
        try PersistenceCoding.decode(TrainingPlan.self, from: payload)
    }

    /// Replaces this record's `payload` with `plan`'s, leaving `id` unchanged.
    ///
    /// - Parameter plan: The plan to update this record from.
    public func update(from plan: TrainingPlan) throws {
        payload = try PersistenceCoding.encode(plan)
    }
}
