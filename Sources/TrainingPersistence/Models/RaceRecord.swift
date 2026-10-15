import TrainingCore
import Foundation
import SwiftData

/// The persisted row for a `Race`. See ``ActivityRecord`` for why this is a JSON payload plus one
/// indexed lookup field rather than one attribute per model field, why the class and `id` are
/// public, and why `payload` isn't.
@Model
public final class RaceRecord {
    /// Mirrors `Race.id`.
    public var id: UUID = UUID()
    /// The JSON-encoded `Race`.
    var payload: Data = Data()

    init(id: UUID, payload: Data) {
        self.id = id
        self.payload = payload
    }
}

extension RaceRecord {
    /// Creates a race record by encoding `race`.
    ///
    /// - Parameter race: The race to persist.
    public convenience init(race: Race) throws {
        self.init(id: race.id, payload: try PersistenceCoding.encode(race))
    }

    /// Decodes `payload` back into a `Race`.
    public func toRace() throws -> Race {
        try PersistenceCoding.decode(Race.self, from: payload)
    }

    /// Replaces this record's `payload` with `race`'s, leaving `id` unchanged.
    ///
    /// - Parameter race: The race to update this record from.
    public func update(from race: Race) throws {
        payload = try PersistenceCoding.encode(race)
    }
}
