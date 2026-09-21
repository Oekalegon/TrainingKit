import Foundation

/// Storage contract for completed activities.
public protocol ActivityStore: Sendable {
    /// All activities whose `start` falls within `range`, with any activity that has been joined
    /// into another (see ``saveJoin(_:components:replacing:)``) hidden and the joined activity
    /// shown in its place — so callers (fitness recompute, overlap checks, the UI) see one
    /// activity for a joined session without having to know it was ever split.
    ///
    /// A joined activity is included when *any* of its components starts in `range`, even if its
    /// own `start` (the earliest component's) falls before it, so a range boundary never shows one
    /// piece on its own. Lookups by id/source (``activity(id:)``, ``activity(source:)``) still
    /// find hidden components.
    func activities(in range: ClosedRange<Date>) async throws -> [Activity]

    /// Inserts new activities or replaces existing ones matched by `id`.
    ///
    /// Also matched by `source` (except sources with no natural key of their own — `.manual` and
    /// `.testing`, see ``ActivitySource/hasNaturalKey`` — which are never deduped against other
    /// entries of the same case): an incoming activity whose `source` already
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

    /// Removes the activity with this id, if any — the resolution action for a specific
    /// ``ActivityOverlapChecker`` pair (MVP1-63), as distinct from ``deleteActivity(source:)``
    /// (which removes whatever's currently on a given source, regardless of id).
    ///
    /// Deleting a joined activity removes its components too (each tombstoned like any other
    /// deleted activity) — "delete this activity" means the whole session — except any component
    /// that another join still uses, which stays. Use
    /// ``unjoinActivity(id:)`` to split it back into its pieces instead.
    func deleteActivity(id: UUID) async throws

    /// The subset of `sources` that were deleted via ``deleteActivity(id:)`` and haven't been
    /// re-added since — a fresh ``upsert(_:)`` for a given source clears its tombstone. This is
    /// the resurrection check ``TrainingModel``'s import path (MVP1-64) runs before persisting
    /// whatever an ``ActivityImporting`` conformer reports, so a resolved duplicate/conflict
    /// doesn't come back under a new id just because the external source still reports it.
    ///
    /// Only sources with a natural key (see ``ActivitySource/hasNaturalKey``) are ever
    /// tombstoned — `.manual`/`.testing` activities are never deduped against each other on
    /// re-import in the first place, so there's nothing here to guard.
    func tombstonedSources(among sources: [ActivitySource]) async throws -> Set<ActivitySource>

    /// Removes duplicate records that share the same `source` with a natural key (see
    /// ``ActivitySource/hasNaturalKey``), keeping exactly one per source.
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

    /// Stores `merged` — one activity standing in for a session that was recorded in pieces — and
    /// records that `components` are its pieces, in a single atomic step.
    ///
    /// The components stay in the store untouched (still keyed by their own `source`, so a
    /// re-import keeps updating them in place and never resurrects them as separate activities),
    /// but ``activities(in:)`` hides them from now on. ``unjoinActivity(id:)`` reverses this.
    ///
    /// Storing a join under an existing joined activity's own id (with `replacing` empty) rebuilds it
    /// in place.
    ///
    /// - Throws: ``ActivityJoinError/componentAlreadyJoined(_:)`` if any of `components` already
    ///   belongs to a different join that isn't in `replacedJoinIDs`; nothing is stored then.
    ///
    /// - Parameters:
    ///   - merged: The combined activity to store.
    ///   - components: The ids of the underlying, non-joined activities it was built from.
    ///   - replacedJoinIDs: Ids of existing joined activities that `merged` supersedes (because
    ///     one of them was itself joined further); each one's activity and link is removed. Their
    ///     components must be included in `components`.
    func saveJoin(_ merged: Activity, components: [UUID], replacing replacedJoinIDs: [UUID]) async throws

    /// The joined activity that `componentID` is a piece of, if any — how an import finds the join a
    /// changed or removed piece belongs to.
    func joinedActivity(containing componentID: UUID) async throws -> Activity?

    /// The component activities `id`'s joined activity was built from, earliest first, or an empty
    /// array if `id` isn't a joined activity.
    func components(ofJoinedActivity id: UUID) async throws -> [Activity]

    /// Undoes a join: removes the joined activity `id` and its link, so its components show up
    /// individually again. A no-op if `id` isn't a joined activity.
    func unjoinActivity(id: UUID) async throws
}
