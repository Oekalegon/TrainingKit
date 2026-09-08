import Foundation

/// Storage contract for completed activities.
public protocol ActivityStore: Sendable {
    /// All activities whose `start` falls within `range`.
    func activities(in range: ClosedRange<Date>) async throws -> [Activity]

    /// Inserts new activities or replaces existing ones matched by `id`.
    ///
    /// Also matched by `source` (except `.manual`, which has no natural key of its own and is
    /// never deduped against other manual entries): an incoming activity whose `source` already
    /// belongs to a *different* existing `id` replaces that record instead of inserting a second
    /// one. This is defense-in-depth, not the primary dedupe path — callers are expected to look up
    /// ``activity(source:)`` and reuse its `id` before calling this, and ``TrainingModel``'s own
    /// import path (see ``ActivityImporting``) does exactly that — but it makes `upsert` itself
    /// safe against a caller that skips that lookup, or a source ending up attached to two ids for
    /// any other reason (e.g. a merge race), rather than silently accumulating duplicate rows.
    func upsert(_ activities: [Activity]) async throws

    /// The activity from this exact source, if one has already been imported — the dedupe check
    /// a re-import should perform before inserting.
    func activity(source: ActivitySource) async throws -> Activity?

    /// The activity with this id, if any.
    func activity(id: UUID) async throws -> Activity?

    /// Removes the activity from this source, if any — the delete half of an ``ActivityImporting``
    /// run that reports a source as removed at the origin.
    func deleteActivity(source: ActivitySource) async throws

    /// Removes duplicate records that share the same non-manual `source`, keeping exactly one per
    /// source.
    ///
    /// A one-time cleanup for duplicates already persisted before `upsert(_:)`'s defense-in-depth
    /// dedup existed — `upsert` only clears a stale duplicate when a *new* activity for that
    /// source arrives, so it never retroactively fixes rows already sitting in the store from
    /// before that logic shipped.
    ///
    /// - Returns: The activities that were removed, sorted by `start`, so a caller can invalidate
    ///   anything keyed on their dates (e.g. a fitness-metrics cache).
    @discardableResult
    func deduplicateActivities() async throws -> [Activity]
}
