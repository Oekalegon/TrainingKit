import Foundation

/// The observable facade the app builds its UI on: owns the current activities/plans/workouts/
/// cycles/metrics, and keeps them in sync with the stores.
///
/// `importActivities(from:)` lives in a separate extension, ``TrainingModel/importActivities(from:asOf:)``.
///
/// `cycleStats`/`evaluation` (design doc §3.3) aren't implemented yet — they depend on
/// ``TrainingCore``'s periodisation-statistics and plan-evaluator work, none of which exist yet.
/// They'll be added as small, additive extensions once those land.
@Observable
@MainActor
public final class TrainingModel {
    public internal(set) var activities: [Activity] = []
    public private(set) var plans: [PlannedActivity] = []
    public private(set) var workouts: [StructuredWorkout] = []
    public private(set) var cycles: [TrainingCycle] = []
    public private(set) var metrics: [FitnessMetrics] = []
    /// Whether an ``ActivityImporting`` run (e.g. HealthKit) has ever completed successfully for
    /// this athlete, independent of `activities.isEmpty` — set from ``AthleteStore/importAnchor()``
    /// by ``load(in:asOf:)``, and never cleared once true by ``importActivities(from:asOf:)``.
    ///
    /// `activities.isEmpty` only reflects whichever range those two last loaded, so an athlete who
    /// connected and imported months ago but has no activity in the currently displayed range
    /// would otherwise look indistinguishable from one who never connected at all. Callers
    /// building a first-run "connect" prompt (design doc §2.1) should gate on this instead.
    ///
    /// Deliberately monotonic within a session: an ``ActivityImporting`` conformer is allowed to
    /// return a `nil` ``ImportResult/anchor`` (e.g. one that doesn't support incremental import),
    /// which would otherwise read back as "never imported" on the very next `load(in:)` even
    /// though an import just completed. `load(in:)` still re-derives this from the persisted
    /// anchor on every call, so a `false` from a genuinely never-connected athlete is unaffected —
    /// only a same-session `true` survives a later `nil`-anchor import.
    public internal(set) var hasEverImportedActivities = false
    /// The athlete this model reflects. A plain, caller-managed property — `TrainingModel` doesn't
    /// automatically load or save it via `AthleteStore`.
    ///
    /// When a ``StoreSet/fitnessMetricsCacheStore`` is configured, reassigning this marks the
    /// persisted cache dirty (see ``recompute(asOf:)``): a newly *added*
    /// ``AthleteProfile/heartRateZoneHistory`` entry (a fresh `effectiveDate` not present before)
    /// invalidates only from its earliest new `effectiveDate` forward (since
    /// ``AthleteProfile/heartRateZoneSettings(asOf:)`` only ever looks backward from an activity's
    /// date, a zone change can't affect anything earlier). Editing an existing entry in place
    /// (same `effectiveDate`, different bpm values), removing one, or changing any other athlete
    /// field (`sex`, `paceModel`, `timeZone`, `weekStartsOn`) isn't date-scoped the same way, so it
    /// conservatively invalidates the entire cache instead.
    public var athlete: AthleteProfile {
        didSet {
            guard athlete != oldValue else { return }
            let oldDates = Set(oldValue.heartRateZoneHistory.map(\.effectiveDate))
            let changedDates = athlete.heartRateZoneHistory
                .map(\.effectiveDate)
                .filter { !oldDates.contains($0) }
            let invalidateFrom: Date
            if let earliestZoneChange = changedDates.min(),
                athlete.sex == oldValue.sex, athlete.paceModel == oldValue.paceModel,
                athlete.timeZone == oldValue.timeZone, athlete.weekStartsOn == oldValue.weekStartsOn {
                invalidateFrom = earliestZoneChange
            } else {
                invalidateFrom = .distantPast
            }
            pendingCacheInvalidation = min(pendingCacheInvalidation ?? .distantFuture, invalidateFrom)
        }
    }
    /// EWMA time constants and monotony window used by ``recompute(asOf:)``.
    ///
    /// Reassigning this always fully invalidates the persisted cache (if configured) — the time
    /// constants and monotony window aren't date-scoped, so any change reshapes every cached day's
    /// CTL/ATL/TSB/monotony/strain.
    public var parameters: LoadModelParameters {
        didSet {
            guard parameters != oldValue else { return }
            pendingCacheInvalidation = min(pendingCacheInvalidation ?? .distantFuture, .distantPast)
        }
    }

    let stores: StoreSet
    private let estimator: any PlannedLoadEstimator
    private let calculators: [any LoadCalculator]
    var loadedRange: ClosedRange<Date>?
    /// Set by ``athlete``'s/``parameters``'s `didSet` when a ``StoreSet/fitnessMetricsCacheStore``
    /// is configured; consumed and cleared by ``recompute(asOf:)``, which is what every existing
    /// mutator already calls right after changing either property. Stashed here (not written to
    /// the store immediately) because `didSet` can't `await`, and `TrainingModel` being
    /// `@MainActor` makes this synchronous stash-then-consume safe from races.
    private var pendingCacheInvalidation: Date?
    /// The most recently scheduled ``importActivities(from:asOf:)``/``resyncActivities(from:asOf:)``
    /// run, if one hasn't finished yet. Chained (not replaced) by each new call so imports always
    /// execute one at a time — see the doc comment on ``importActivities(from:asOf:)`` for why.
    var pendingImport: Task<Void, Error>?
    /// The most recently scheduled ``recompute(asOf:)`` run, if one hasn't finished yet. Chained
    /// (not replaced) by each new call, the same way ``TrainingModel/pendingImport`` chains
    /// `importActivities(from:)`/`resyncActivities(from:)` calls, and for the same reason: without
    /// it, two overlapping recomputes (e.g. one triggered by `add(_ plan:)`, another by an import
    /// finishing at nearly the same moment) could both read the fitness-metrics cache's dirty
    /// watermark before either has cleared it, race on `upsert`-ing the same recomputed days, or
    /// have the second's `clearDirtyWatermark()` drop an invalidation the first was still working
    /// through. Deliberately a *separate* chain from ``pendingImport``, not the same one: every
    /// import already calls `recompute(asOf:)` itself at its tail, and reusing `pendingImport` here
    /// would make that call wait on its own still-in-flight import task — a guaranteed deadlock.
    private var pendingRecompute: Task<Void, Never>?

    /// Creates a training model.
    ///
    /// - Parameters:
    ///   - stores: Where activities/plans/workouts/cycles/the athlete profile are persisted.
    ///   - athlete: The athlete this model reflects.
    ///   - parameters: EWMA time constants and monotony window; defaults to the standard values.
    ///   - estimator: Estimates load for planned activities; defaults to ``TRIMPPlanEstimator``.
    ///   - calculators: Tried in order per activity; defaults to
    ///     ``ExponentialTRIMPCalculator``/``DurationRPECalculator``.
    public init(
        stores: StoreSet,
        athlete: AthleteProfile,
        parameters: LoadModelParameters = LoadModelParameters(),
        estimator: any PlannedLoadEstimator = TRIMPPlanEstimator(),
        calculators: [any LoadCalculator] = [ExponentialTRIMPCalculator(), DurationRPECalculator()]
    ) {
        self.stores = stores
        self.athlete = athlete
        self.parameters = parameters
        self.estimator = estimator
        self.calculators = calculators
    }

    /// Fetches activities/plans/cycles in `range` and the full workout library from the stores,
    /// then recomputes. Call once at startup, and again if the visible range changes.
    ///
    /// Fetches into locals first and only assigns once all four succeed, so a failure partway
    /// through (e.g. the plan fetch throwing after the activity fetch already succeeded) leaves
    /// this model exactly as it was before the call, rather than a mix of the old and new range.
    public func load(in range: ClosedRange<Date>, asOf today: Date = .now) async throws {
        let newActivities = try await stores.activityStore.activities(in: range)
        let newPlans = try await stores.planStore.plans(in: range)
        let newWorkouts = try await stores.workoutStore.workouts()
        let newCycles = try await stores.cycleStore.cycles(in: range)
        let newHasEverImportedActivities = try await stores.athleteStore.importAnchor() != nil

        activities = newActivities
        plans = newPlans
        workouts = newWorkouts
        cycles = newCycles
        hasEverImportedActivities = newHasEverImportedActivities
        loadedRange = range
        await recompute(asOf: today)
    }

    /// Upserts `plan` into ``PlanStore``, reloads plans and the workout library from the store,
    /// and recomputes.
    ///
    /// If ``load(in:asOf:)`` hasn't been called yet, this falls back to a range covering just
    /// `plan.date` (and adopts it as the loaded range) rather than silently skipping the reload —
    /// without this, the plan would persist to the store but `plans`/`metrics` would never reflect
    /// it, with no error to signal anything was skipped.
    public func add(_ plan: PlannedActivity, asOf today: Date = .now) async throws {
        try await stores.planStore.upsert([plan])
        let range = loadedRange ?? (plan.date...plan.date)
        plans = try await stores.planStore.plans(in: range)
        // Always refreshed (not just when never loaded): recompute needs `workouts` to resolve
        // `plan.workoutID`, and the workout `plan` references might not be in the cached array yet.
        workouts = try await stores.workoutStore.workouts()
        loadedRange = range
        await recompute(asOf: today)
    }

    /// Upserts `newCycles` into ``CycleStore``, reloads cycles from the store, and recomputes.
    ///
    /// If `load(in:asOf:)` hasn't been called yet, this falls back to a range covering the union
    /// of `newCycles`' date ranges (and adopts it as the loaded range), for the same reason as the
    /// `PlannedActivity` overload of `add` above.
    public func add(_ newCycles: [TrainingCycle], asOf today: Date = .now) async throws {
        try await stores.cycleStore.upsert(newCycles)
        let range = loadedRange ?? Self.union(of: newCycles.map(\.dateRange), fallback: today)
        cycles = try await stores.cycleStore.cycles(in: range)
        loadedRange = range
        await recompute(asOf: today)
    }

    /// Rebuilds ``metrics``.
    ///
    /// `today` is injected, never read from `Date()` internally, for the same determinism reason
    /// as ``DailyLoadSeries``. The actual series/metrics computation runs off the main actor.
    ///
    /// Without a ``StoreSet/fitnessMetricsCacheStore``, this recomputes the full daily series from
    /// `activities`/`plans`/`workouts` every time, exactly as before this cache existed. With one
    /// configured, it instead recomputes only the "dirty tail" — from any pending invalidation
    /// (see ``athlete``/``parameters``) or wherever the cache last left off, seeded from the last
    /// cached day — persists newly-final (`day < today`) results, and assembles ``metrics`` for
    /// `loadedRange` from cached rows plus the freshly computed, never-persisted volatile tail
    /// (`today` and any projected/future day).
    ///
    /// Serialized against any other in-flight `recompute(asOf:)` call via ``pendingRecompute``, for
    /// the same TOCTOU reason ``importActivities(from:asOf:)`` serializes against
    /// ``pendingImport``: without it, two overlapping recomputes could both read
    /// ``pendingCacheInvalidation``/the cache's dirty watermark before either has cleared it, and
    /// the second's completion could drop an invalidation the first was still working through.
    public func recompute(asOf today: Date = .now) async {
        let previous = pendingRecompute
        let task = Task {
            await previous?.value
            await self.performRecompute(asOf: today)
        }
        pendingRecompute = task
        await task.value
    }

    private func performRecompute(asOf today: Date) async {
        guard let cache = stores.fitnessMetricsCacheStore else {
            metrics = await Self.buildMetricsWithoutCache(
                activities: activities,
                plans: plans,
                publishRange: loadedRange ?? (today...today),
                workouts: workouts,
                estimator: estimator,
                calculators: calculators,
                athlete: athlete,
                parameters: parameters,
                today: today
            )
            return
        }

        if let pending = pendingCacheInvalidation {
            try? await cache.markDirty(from: pending)
            pendingCacheInvalidation = nil
        }

        metrics = await Self.buildMetricsWithCache(
            cache: cache,
            stores: stores,
            publishRange: loadedRange ?? (today...today),
            workouts: workouts,
            estimator: estimator,
            calculators: calculators,
            athlete: athlete,
            parameters: parameters,
            today: today
        )
    }

    /// The smallest range covering every range in `ranges`, or `fallback...fallback` if `ranges`
    /// is empty.
    static func union(of ranges: [ClosedRange<Date>], fallback: Date) -> ClosedRange<Date> {
        guard let first = ranges.first else { return fallback...fallback }
        return ranges.dropFirst().reduce(first) { partial, range in
            min(partial.lowerBound, range.lowerBound)...max(partial.upperBound, range.upperBound)
        }
    }

    /// Pure computation extracted so it runs off the main actor: calling a `nonisolated async`
    /// function from `@MainActor` code dispatches it onto the cooperative thread pool rather than
    /// running inline on the main actor's executor.
    ///
    /// The no-cache path: recomputes the entire series from `activities`/`plans` every call,
    /// unseeded — exactly ``recompute(asOf:)``'s behavior before the persisted cache existed.
    ///
    /// `publishRange` only pads the *tail*: ``DailyLoadSeries/days(activities:plans:workouts:estimator:calculators:athlete:today:)``
    /// already spans back to the earliest activity/plan (or `today`, whichever is earlier) on its
    /// own, but stops at the latest activity/plan (or `today`, whichever is *later*) — a
    /// `publishRange` extending further into the future than the last planned activity would
    /// otherwise leave those trailing days missing from `metrics` entirely rather than present with
    /// zero load. See ``paddedForward(_:through:calendar:)``.
    private nonisolated static func buildMetricsWithoutCache(
        activities: [Activity],
        plans: [PlannedActivity],
        publishRange: ClosedRange<Date>,
        workouts: [StructuredWorkout],
        estimator: any PlannedLoadEstimator,
        calculators: [any LoadCalculator],
        athlete: AthleteProfile,
        parameters: LoadModelParameters,
        today: Date
    ) async -> [FitnessMetrics] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = athlete.timeZone

        var days = DailyLoadSeries().days(
            activities: activities,
            plans: plans,
            workouts: workouts,
            estimator: estimator,
            calculators: calculators,
            athlete: athlete,
            today: today
        )
        days = paddedForward(days, through: publishRange.upperBound, calendar: calendar)
        return FitnessMetricsCalculator().metrics(for: days, parameters: parameters, seed: nil)
    }

    /// Appends zero-load, projected days to `days` from the day after its last entry through
    /// the calendar day containing `upperBound`, inclusive — a no-op if `days` is already empty or
    /// already reaches that day. Shared by both `buildMetrics*` paths so a `publishRange`-like upper
    /// bound extending past the last real activity/plan doesn't silently truncate the published
    /// series instead of zero-filling it.
    ///
    /// `upperBound` is day-aligned internally (via `calendar.startOfDay(for:)`) rather than compared
    /// raw: every `DayLoad`/`FitnessMetrics.day` in this system is a startOfDay-aligned Date, but
    /// `upperBound` (e.g. `publishRange.upperBound`) is a caller-supplied instant that's rarely
    /// exactly midnight — comparing against it raw would overshoot by one extra day whenever it
    /// falls after midnight on its own calendar day.
    private nonisolated static func paddedForward(
        _ days: [DayLoad], through upperBound: Date, calendar: Calendar
    ) -> [DayLoad] {
        let targetDay = calendar.startOfDay(for: upperBound)
        guard var day = days.last?.day, day < targetDay else { return days }
        var result = days
        while day < targetDay {
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
            result.append(DayLoad(day: day, load: 0, isProjected: true))
        }
        return result
    }

    /// The cache-aware path, used by ``recompute(asOf:)`` when a
    /// ``StoreSet/fitnessMetricsCacheStore`` is configured.
    ///
    /// Recomputes only from `effectiveFetchFrom` forward (clamped to never exceed `today`/
    /// `publishRange`'s upper bound) — the cache's dirty watermark if one is pending (a full,
    /// `.distantPast` invalidation wipes the cache first, so a change that shifts every `day`
    /// boundary, like a timezone change, can't leave stale rows behind under old boundaries, then
    /// still only recomputes from the wiped cache's own former earliest day forward, not the
    /// literal epoch), else the day after whatever's already cached (clamped to `today`, so an
    /// already-caught-up cache only ever recomputes the volatile today/future tail), else the Unix
    /// epoch if the cache is empty (the one true full-history bootstrap, which only ever happens
    /// once). Fetches activities/plans for that range directly from `stores` — never from
    /// `TrainingModel.activities`/`.plans`, which may
    /// only be a UI-driven subset — seeds CTL/ATL and the monotony window from the cache, computes
    /// forward, persists whatever's newly final (`day < today`), and assembles the result for
    /// `publishRange` from cached rows plus the fresh tail.
    private nonisolated static func buildMetricsWithCache(
        cache: any FitnessMetricsCacheStore,
        stores: StoreSet,
        publishRange: ClosedRange<Date>,
        workouts: [StructuredWorkout],
        estimator: any PlannedLoadEstimator,
        calculators: [any LoadCalculator],
        athlete: AthleteProfile,
        parameters: LoadModelParameters,
        today: Date
    ) async -> [FitnessMetrics] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = athlete.timeZone
        let todayStart = calendar.startOfDay(for: today)
        let bootstrapSentinel = Date(timeIntervalSince1970: 0)

        let watermark = try? await cache.dirtyWatermark()
        // A blanket full-invalidate (`athlete`/`parameters`'s `didSet` uses `.distantPast` to mean
        // "recompute everything cached") needs the cache wiped outright rather than reusing
        // `upsert`'s replace-by-day matching to overwrite it in place: `upsert` matches purely on
        // the `FitnessMetrics.day` Date value, which is computed with `athlete.timeZone` at write
        // time. A timezone change is exactly one of the things that triggers this `.distantPast`
        // path, and it shifts every future `day` value relative to the old rows — `upsert` would
        // then insert alongside the stale rows instead of replacing them, leaving orphaned,
        // wrong-boundary duplicates behind. The actual delete is deferred to below, alongside the
        // rest of this function's cache writes, and only runs once the activity fetch has
        // succeeded — see the `cacheWriteBlocked` guard there: deleting eagerly here, before
        // knowing whether the fetch that's about to compute a replacement even succeeds, would
        // leave the cache empty (not just stale) for as long as the fetch keeps failing.
        let effectiveFetchFrom: Date
        if let watermark {
            if watermark == .distantPast {
                // Still bounded by the cache's own earliest row (read now, before it's deleted),
                // not the literal `.distantPast` sentinel: recomputing from there would pad and
                // recompute every day since roughly year 1, which is an unbounded, unrealistic
                // amount of work (and, via `upsert`, an unbounded write) for what should be "redo
                // however many days were actually cached" — the wipe only needs to guarantee no
                // *stale* row survives, not that the recompute itself reaches back further than
                // the old cache did.
                let earliestBeforeWipe = try? await cache.earliestCachedDay()
                effectiveFetchFrom = earliestBeforeWipe ?? bootstrapSentinel
            } else {
                effectiveFetchFrom = watermark
            }
        } else if let latestCached = try? await cache.latestCachedDay() {
            let nextDay = calendar.date(byAdding: .day, value: 1, to: latestCached) ?? todayStart
            effectiveFetchFrom = min(nextDay, todayStart)
        } else {
            effectiveFetchFrom = bootstrapSentinel
        }

        let upperBound = max(todayStart, publishRange.upperBound)
        // Clamped to `upperBound`, not just day-aligned: `effectiveFetchFrom` can come straight
        // from a dirty watermark (e.g. a newly added `HeartRateZoneSettings.effectiveDate`, which
        // a caller can legitimately set in the future), and an unclamped `fetchFromStart` beyond
        // `upperBound` would build an invalid (`lowerBound > upperBound`) `ClosedRange` below and
        // trap.
        let fetchFromStart = min(calendar.startOfDay(for: effectiveFetchFrom), upperBound)
        // Tracked separately from `?? []` so a failed fetch can't get baked into the cache as if
        // it were a genuine all-rest-day stretch — see the `toCache` guard below. Only the
        // activity fetch gates that guard: `DailyLoadSeries` never reads `plans` for a
        // `day < todayStart` (the only days ever written to the cache), so a `plans`-only failure
        // can't taint what's about to be cached — it only degrades today's/future's *published*
        // estimate, handled separately below.
        let fetchedActivities = try? await stores.activityStore.activities(in: fetchFromStart...upperBound)
        let fetchedPlans = try? await stores.planStore.plans(in: fetchFromStart...upperBound)
        let cacheWriteBlocked = fetchedActivities == nil
        let rawActivities = fetchedActivities ?? []
        let rawPlans = fetchedPlans ?? []

        var days = DailyLoadSeries().days(
            activities: rawActivities,
            plans: rawPlans,
            workouts: workouts,
            estimator: estimator,
            calculators: calculators,
            athlete: athlete,
            today: today
        )

        // `DailyLoadSeries` starts its emitted range at the first day with real activity/plan
        // data, which can be later than `fetchFromStart` if there's a genuine no-activity gap
        // right after the boundary — pad the front so the series still starts exactly where the
        // cache needs it to, with zero load for those in-between days.
        if let firstDay = days.first?.day, firstDay > fetchFromStart {
            var padding: [DayLoad] = []
            var day = fetchFromStart
            while day < firstDay {
                padding.append(DayLoad(day: day, load: 0, isProjected: false))
                day = calendar.date(byAdding: .day, value: 1, to: day) ?? firstDay
            }
            days = padding + days
        } else if days.isEmpty {
            days = [DayLoad(day: fetchFromStart, load: 0, isProjected: false)]
        }

        // Same reasoning as the front-padding above, but at the tail: `DailyLoadSeries` also stops
        // at the latest activity/plan (or `today`, whichever is later), which can be short of
        // `upperBound` if `publishRange` extends further into the future than the last planned
        // activity — without this, those trailing days would be missing from `freshPortion` below
        // entirely, rather than present with zero load.
        days = paddedForward(days, through: upperBound, calendar: calendar)

        let seed: (ctl: Double, atl: Double)?
        let recentLoads: [Double]
        if effectiveFetchFrom == bootstrapSentinel {
            seed = nil
            recentLoads = []
        } else {
            // Seeded from `fetchFromStart` (day-aligned), not the raw `effectiveFetchFrom` — a
            // dirty watermark from `markDirty(from:)` is often a mid-day activity timestamp, and
            // `cachedMetrics(immediatelyBefore:)`/`recentLoads(before:)` against that raw timestamp
            // would find *that same day's own* already-cached (about-to-be-recomputed, stale) row
            // as "immediately before" itself, self-seeding day 1 of this recompute from its own
            // pre-edit value instead of the day before it.
            let priorMetrics = try? await cache.cachedMetrics(immediatelyBefore: fetchFromStart)
            seed = priorMetrics.map { ($0.ctl, $0.atl) }
            recentLoads = (try? await cache.recentLoads(before: fetchFromStart, count: parameters.monotonyWindowDays)) ?? []
        }

        let result = FitnessMetricsCalculator().metrics(
            for: days, parameters: parameters, seed: seed, recentLoads: recentLoads
        )

        // Every cache mutation below is skipped when `activities(in:)` failed:
        // `rawActivities`/`rawPlans` are then an empty stand-in for "unknown," not "no
        // activities," and `result`'s `day < todayStart` portion was computed from that stand-in —
        // persisting it would permanently overwrite this range's real history with a bogus
        // all-rest-day series, since `effectiveFetchFrom` only ever advances forward from the
        // latest *cached* day. Leaving the watermark and any pending `.distantPast` wipe untouched
        // here means the next `recompute(asOf:)` retries this exact range (with the old cache rows
        // — stale, but not empty — still in place) instead of silently keeping wrong data or
        // discarding good data it can't yet replace. A `plans(in:)`-only failure doesn't block any
        // of this: `DailyLoadSeries` never reads `plans` for a `day < todayStart`, so it can't have
        // tainted what's about to be cached — it only degrades today's/future's *published*
        // estimate, which is recomputed fresh (never cached) on every call regardless.
        let toCache = result.filter { $0.day < todayStart }
        if cacheWriteBlocked {
            Logging.series.warning(
                "Skipping fitness-metrics cache write for \(fetchFromStart, privacy: .public)...\(upperBound, privacy: .public): activity fetch failed, will retry on next recompute"
            )
        } else {
            if watermark == .distantPast {
                try? await cache.deleteCachedMetrics(from: .distantPast)
            }
            if !toCache.isEmpty {
                try? await cache.upsert(toCache)
            }
            try? await cache.clearDirtyWatermark()
        }
        if fetchedPlans == nil {
            Logging.series.warning(
                "Fitness-metrics recompute for \(fetchFromStart, privacy: .public)...\(upperBound, privacy: .public) proceeded with an empty plan set: plan fetch failed, today's/future's published estimate may be understated until the next recompute"
            )
        }

        var cachedPortion: [FitnessMetrics] = []
        if let cachedUpperExclusive = calendar.date(byAdding: .day, value: -1, to: fetchFromStart),
            publishRange.lowerBound <= cachedUpperExclusive {
            let cachedRange = publishRange.lowerBound...min(cachedUpperExclusive, publishRange.upperBound)
            cachedPortion = (try? await cache.cachedMetrics(in: cachedRange)) ?? []
        }
        let freshPortion = result.filter { publishRange.contains($0.day) }

        return (cachedPortion + freshPortion).sorted { $0.day < $1.day }
    }
}
