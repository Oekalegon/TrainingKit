import TrainingCore
import Foundation
import SwiftData

/// The persisted row for a `TrainingCycle`. See ``ActivityRecord`` for why this is a JSON payload
/// plus one indexed lookup field rather than one attribute per model field, why the class and
/// `id` are public, and why `payload` isn't.
@Model
public final class TrainingCycleRecord {
    /// Mirrors `TrainingCycle.id`.
    public var id: UUID = UUID()
    /// The JSON-encoded `TrainingCycle`.
    var payload: Data = Data()

    init(id: UUID, payload: Data) {
        self.id = id
        self.payload = payload
    }
}

extension TrainingCycleRecord {
    /// Creates a training-cycle record by encoding `cycle`.
    ///
    /// - Parameter cycle: The cycle to persist.
    public convenience init(cycle: TrainingCycle) throws {
        self.init(id: cycle.id, payload: try PersistenceCoding.encode(cycle))
    }

    /// Decodes `payload` back into a `TrainingCycle`.
    public func toCycle() throws -> TrainingCycle {
        try PersistenceCoding.decode(TrainingCycle.self, from: payload)
    }

    /// Replaces this record's `payload` with `cycle`'s, leaving `id` unchanged.
    ///
    /// - Parameter cycle: The cycle to update this record from.
    public func update(from cycle: TrainingCycle) throws {
        payload = try PersistenceCoding.encode(cycle)
    }
}
