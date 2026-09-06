import TrainingCore
import Foundation
import SwiftData

/// The persisted row for a `PlannedActivity`. See ``ActivityRecord`` for why this is a JSON
/// payload plus one indexed lookup field rather than one attribute per model field, why the class
/// and `id` are public, and why `payload` isn't.
@Model
public final class PlannedActivityRecord {
    /// Mirrors `PlannedActivity.id`.
    public var id: UUID = UUID()
    /// The JSON-encoded `PlannedActivity`.
    var payload: Data = Data()

    init(id: UUID, payload: Data) {
        self.id = id
        self.payload = payload
    }
}

extension PlannedActivityRecord {
    /// Creates a planned-activity record by encoding `plan`.
    ///
    /// - Parameter plan: The plan to persist.
    public convenience init(plan: PlannedActivity) throws {
        self.init(id: plan.id, payload: try PersistenceCoding.encode(plan))
    }

    /// Decodes `payload` back into a `PlannedActivity`.
    public func toPlan() throws -> PlannedActivity {
        try PersistenceCoding.decode(PlannedActivity.self, from: payload)
    }

    /// Replaces this record's `payload` with `plan`'s, leaving `id` unchanged.
    ///
    /// - Parameter plan: The plan to update this record from.
    public func update(from plan: PlannedActivity) throws {
        payload = try PersistenceCoding.encode(plan)
    }
}
