import Foundation

/// Storage contract for races.
public protocol RaceStore: Sendable {
    /// All races whose `date` falls within `range`.
    func races(in range: ClosedRange<Date>) async throws -> [Race]

    /// The race with this id, if any.
    func race(id: UUID) async throws -> Race?

    /// Inserts new races or replaces existing ones matched by `id`.
    func upsert(_ races: [Race]) async throws

    /// Removes the race with this id, if any. A no-op if `id` doesn't exist.
    func deleteRace(id: UUID) async throws
}
