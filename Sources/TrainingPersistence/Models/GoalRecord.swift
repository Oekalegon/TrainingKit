import TrainingCore
import Foundation
import SwiftData

/// The persisted row for a `Goal`. See ``ActivityRecord`` for why this is a JSON payload plus one
/// indexed lookup field rather than one attribute per model field, why the class and `id` are
/// public, and why `payload` isn't.
@Model
public final class GoalRecord {
    /// Mirrors `Goal.id`.
    public var id: UUID = UUID()
    /// The JSON-encoded `Goal`.
    var payload: Data = Data()

    init(id: UUID, payload: Data) {
        self.id = id
        self.payload = payload
    }
}

extension GoalRecord {
    /// Creates a goal record by encoding `goal`.
    ///
    /// - Parameter goal: The goal to persist.
    public convenience init(goal: Goal) throws {
        self.init(id: goal.id, payload: try PersistenceCoding.encode(goal))
    }

    /// Decodes `payload` back into a `Goal`.
    public func toGoal() throws -> Goal {
        try PersistenceCoding.decode(Goal.self, from: payload)
    }

    /// Replaces this record's `payload` with `goal`'s, leaving `id` unchanged.
    ///
    /// - Parameter goal: The goal to update this record from.
    public func update(from goal: Goal) throws {
        payload = try PersistenceCoding.encode(goal)
    }
}
