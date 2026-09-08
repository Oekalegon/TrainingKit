import Foundation

/// Storage contract for the persisted CTL/ATL/TSB/monotony/strain cache.
///
/// Only **final** days are ever stored here — a day whose `FitnessMetrics` was computed with
/// `day < today` at the time it was written. `today` and every projected/future day are always
/// computed fresh by ``TrainingModel`` and never read from or written to this store, since those
/// change on every new activity and on every calendar-day rollover.
public protocol FitnessMetricsCacheStore: Sendable {
    /// Cached metrics for every day in `range`, in any order.
    func cachedMetrics(in range: ClosedRange<Date>) async throws -> [FitnessMetrics]

    /// The latest cached day with `day < date`, if any — the seed source for resuming CTL/ATL
    /// computation at `date`.
    func cachedMetrics(immediatelyBefore date: Date) async throws -> FitnessMetrics?

    /// The trailing `count` cached days' raw `load`, immediately before `date`, oldest first — the
    /// source for resuming the monotony/strain rolling window at `date`. May return fewer than
    /// `count` entries near the start of the cache's history.
    func recentLoads(before date: Date, count: Int) async throws -> [Double]

    /// The latest (most recent) cached day, or `nil` if the cache is empty.
    func latestCachedDay() async throws -> Date?

    /// The earliest cached day, or `nil` if the cache is empty.
    func earliestCachedDay() async throws -> Date?

    /// Inserts new cached rows, or replaces existing ones for the same `day`.
    func upsert(_ metrics: [FitnessMetrics]) async throws

    /// Deletes every cached row with `day >= date`.
    func deleteCachedMetrics(from date: Date) async throws

    /// The current dirty watermark: everything from this date forward needs recomputing. `nil`
    /// means no explicit invalidation is pending (the cache may still need extending forward
    /// simply because time has passed since ``latestCachedDay()`` — that's not tracked here).
    func dirtyWatermark() async throws -> Date?

    /// Lowers the dirty watermark to `date` if `date` is earlier than the current watermark (or if
    /// none is set yet). Never raises it, so two invalidations racing (e.g. an import and an
    /// athlete-profile change) leave the watermark at the earlier of the two, regardless of order.
    func markDirty(from date: Date) async throws

    /// Clears the dirty watermark — call once a recompute has caught the cache up through it.
    func clearDirtyWatermark() async throws
}
