import Foundation

/// Storage contract for completed activities.
public protocol ActivityStore: Sendable {
    /// All activities whose `start` falls within `range`.
    func activities(in range: ClosedRange<Date>) async throws -> [Activity]

    /// Inserts new activities or replaces existing ones matched by `id`.
    func upsert(_ activities: [Activity]) async throws

    /// The activity from this exact source, if one has already been imported — the dedupe check
    /// a re-import should perform before inserting.
    func activity(source: ActivitySource) async throws -> Activity?

    /// The activity with this id, if any.
    func activity(id: UUID) async throws -> Activity?

    /// Removes the activity from this source, if any — the delete half of an ``ActivityImporting``
    /// run that reports a source as removed at the origin.
    func deleteActivity(source: ActivitySource) async throws
}
