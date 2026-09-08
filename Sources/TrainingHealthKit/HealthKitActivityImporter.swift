import TrainingCore
import Foundation

#if canImport(HealthKit)
import HealthKit
import os

private let importLogger = Logger(subsystem: "com.trainingKit", category: "Import")

/// Imports completed workouts and their heart-rate samples from HealthKit.
///
/// - `HKAnchoredObjectQueryDescriptor` on `HKWorkoutType` reports workouts added, updated, or
///   deleted since the last anchor; the anchor is archived into `ImportAnchor.data` and handed
///   back unchanged for `TrainingCore` to persist via `AthleteStore`.
/// - For each added/updated workout, a separate `HKSampleQueryDescriptor` on `heartRate` scoped to
///   the workout's `startDate...endDate` supplies its `[HeartRateSample]`. High-frequency in-workout
///   heart rate (Apple Watch, AirPods) is stored as `HKQuantitySeriesSample` series anchors rather
///   than one discrete sample per reading; any returned sample with `count > 1` is unpacked via
///   `HKQuantitySeriesSampleQueryDescriptor` to recover the individual readings.
/// - `Activity.source = .healthKit(workout.uuid)` is the stable dedupe key across re-imports, but
///   `ActivityStore.upsert(_:)` matches by `id`, not `source` — so when `activityStore` is supplied,
///   a workout already on record has its existing `id` looked up and reused, rather than every
///   reported workout (added *or* updated — HealthKit reports a modified workout back through the
///   same "added" channel) turning into a second row for the same source.
public struct HealthKitActivityImporter: ActivityImporting {
    /// How many workouts are fetched (heart rate + existing-id lookup) concurrently during
    /// `importActivities(since:)`. See that method's doc comment for why this is bounded rather
    /// than unbounded.
    private static let maxConcurrentWorkouts = 8

    private let healthStore: HKHealthStore
    private let activityStore: (any ActivityStore)?

    /// Creates a HealthKit activity importer.
    ///
    /// - Parameters:
    ///   - healthStore: The health store to import from; the caller is responsible for requesting
    ///     authorization first (see ``HealthKitAuthorization``).
    ///   - activityStore: Used to look up an existing activity's `id` by source before
    ///     constructing a re-imported workout's `Activity`, so `ActivityStore.upsert(_:)` replaces
    ///     it rather than adding a duplicate. Pass `nil` only if the caller reconciles ids itself
    ///     before upserting `ImportResult.upserted`.
    public init(healthStore: HKHealthStore, activityStore: (any ActivityStore)? = nil) {
        self.healthStore = healthStore
        self.activityStore = activityStore
    }

    /// See `ActivityImporting.importActivities(since:)`.
    ///
    /// - Throws: ``HealthKitImportError/corruptAnchor`` if `anchor` doesn't decode as an
    ///   `HKQueryAnchor`; any error HealthKit itself throws (e.g. denied authorization).
    public func importActivities(since anchor: ImportAnchor?) async throws -> ImportResult {
        let workoutAuthStatus = healthStore.authorizationStatus(for: HKObjectType.workoutType())
        importLogger.debug(
            "importActivities(since:) starting, anchor is \(anchor == nil ? "nil (full import)" : "set", privacy: .public), workoutType authorizationStatus \(workoutAuthStatus.rawValue, privacy: .public)"
        )

        let hkAnchor = try anchor.map(Self.decode)

        let descriptor = HKAnchoredObjectQueryDescriptor(
            predicates: [.workout()],
            anchor: hkAnchor
        )
        importLogger.debug("importActivities(since:) awaiting anchored workout query result...")
        let result = try await descriptor.result(for: healthStore)
        importLogger.debug(
            "importActivities(since:) anchored workout query returned \(result.addedSamples.count, privacy: .public) added, \(result.deletedObjects.count, privacy: .public) deleted"
        )

        // Concurrent per workout, but capped at `maxConcurrentWorkouts`: a full first import can be
        // hundreds or thousands of sessions, each needing its own heart-rate query (itself now
        // potentially several more round-trips, one per series sample — see `heartRateSamples(for:)`)
        // and, if `activityStore` is set, an existing-id lookup against a single serialized actor.
        // Launching all of them at once floods both HealthKit's query queue and that actor's mailbox
        // — in practice this manifested as the importer appearing to hang indefinitely on a full
        // historical re-sync. Capping how many workouts are in flight at once keeps the concurrency
        // win the unbounded version was going for without the fan-out that caused that.
        let activities = try await withThrowingTaskGroup(of: Activity.self) { group in
            var remaining = result.addedSamples.makeIterator()
            func addNextTask() {
                guard let workout = remaining.next() else { return }
                group.addTask {
                    async let heartRateTask = heartRateSamples(for: workout)
                    async let existingIDTask = activityStore?.activity(source: .healthKit(workout.uuid))?.id
                    let heartRate = try await heartRateTask
                    let existingID = try await existingIDTask
                    return Activity(healthKitWorkout: workout, heartRate: heartRate, existingID: existingID)
                }
            }
            for _ in 0..<Self.maxConcurrentWorkouts {
                addNextTask()
            }
            var activities: [Activity] = []
            activities.reserveCapacity(result.addedSamples.count)
            for try await activity in group {
                activities.append(activity)
                addNextTask()
            }
            return activities
        }

        let deletedSources = result.deletedObjects.map { ActivitySource.healthKit($0.uuid) }
        let newAnchor = try Self.encode(result.newAnchor)

        return ImportResult(upserted: activities, deletedSources: deletedSources, anchor: newAnchor)
    }

    private func heartRateSamples(for workout: HKWorkout) async throws -> [HeartRateSample] {
        let predicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.heartRate), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let samples = try await descriptor.result(for: healthStore)
        let firstSampleDate = samples.first?.startDate
        let lastSampleDate = samples.last?.startDate
        importLogger.debug(
            """
            heartRateSamples(for:) workout \(workout.uuid, privacy: .public) \
            window \(workout.startDate, privacy: .public)...\(workout.endDate, privacy: .public) \
            source \(workout.sourceRevision.source.bundleIdentifier, privacy: .public) \
            returned \(samples.count, privacy: .public) samples, \
            first \(String(describing: firstSampleDate), privacy: .public) \
            last \(String(describing: lastSampleDate), privacy: .public)
            """
        )

        // A sample whose `count` is > 1 is a series anchor (e.g. Apple Watch/AirPods' high-frequency
        // in-workout heart rate): its own `.quantity`/`.startDate` are just the series' bookkeeping,
        // and the actual per-reading values must be unpacked via `HKQuantitySeriesSampleQueryDescriptor`.
        var expanded: [HeartRateSample] = []
        expanded.reserveCapacity(samples.count)
        for sample in samples {
            if sample.count > 1 {
                expanded.append(contentsOf: try await seriesSamples(for: sample))
            } else {
                expanded.append(HeartRateSample(healthKitQuantitySample: sample))
            }
        }
        expanded.sort { $0.time < $1.time }
        return expanded
    }

    /// Unpacks the individual readings inside a series-anchor `HKQuantitySample` (see
    /// ``heartRateSamples(for:)``).
    private func seriesSamples(for sample: HKQuantitySample) async throws -> [HeartRateSample] {
        let predicate: HKSamplePredicate<HKQuantitySample> = .quantitySample(
            type: HKQuantityType(.heartRate),
            predicate: HKQuery.predicateForObject(with: sample.uuid)
        )
        let descriptor = HKQuantitySeriesSampleQueryDescriptor(predicate: predicate)
        var results: [HeartRateSample] = []
        for try await result in descriptor.results(for: healthStore) {
            results.append(HeartRateSample(
                time: result.dateInterval.start,
                bpm: result.quantity.doubleValue(for: HeartRateSample.heartRateUnit)
            ))
        }
        return results
    }

    private static func encode(_ anchor: HKQueryAnchor) throws -> ImportAnchor {
        let data = try NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
        return ImportAnchor(data: data)
    }

    private static func decode(_ anchor: ImportAnchor) throws -> HKQueryAnchor {
        guard let decoded = try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: anchor.data) else {
            throw HealthKitImportError.corruptAnchor
        }
        return decoded
    }
}
#endif
