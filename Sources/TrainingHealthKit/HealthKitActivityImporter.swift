import TrainingCore
import Foundation

#if canImport(HealthKit)
import HealthKit

/// Imports completed workouts and their heart-rate samples from HealthKit.
///
/// - `HKAnchoredObjectQueryDescriptor` on `HKWorkoutType` reports workouts added, updated, or
///   deleted since the last anchor; the anchor is archived into `ImportAnchor.data` and handed
///   back unchanged for `TrainingCore` to persist via `AthleteStore`.
/// - For each added/updated workout, a separate `HKSampleQueryDescriptor` on `heartRate` scoped to
///   the workout's `startDate...endDate` supplies its `[HeartRateSample]`.
/// - `Activity.source = .healthKit(workout.uuid)` is the stable dedupe key across re-imports, but
///   `ActivityStore.upsert(_:)` matches by `id`, not `source` — so when `activityStore` is supplied,
///   a workout already on record has its existing `id` looked up and reused, rather than every
///   reported workout (added *or* updated — HealthKit reports a modified workout back through the
///   same "added" channel) turning into a second row for the same source.
public struct HealthKitActivityImporter: ActivityImporting {
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
        let hkAnchor = try anchor.map(Self.decode)

        let descriptor = HKAnchoredObjectQueryDescriptor(
            predicates: [.workout()],
            anchor: hkAnchor
        )
        let result = try await descriptor.result(for: healthStore)

        // Concurrent per workout: a full first import can be hundreds of sessions, each needing
        // its own round-trip heart-rate query (and, if activityStore is set, an existing-id
        // lookup) — doing those one at a time would serialize the whole import behind however
        // many workouts there are.
        let activities = try await withThrowingTaskGroup(of: Activity.self) { group in
            for workout in result.addedSamples {
                group.addTask {
                    async let heartRateTask = heartRateSamples(for: workout)
                    async let existingIDTask = activityStore?.activity(source: .healthKit(workout.uuid))?.id
                    let heartRate = try await heartRateTask
                    let existingID = try await existingIDTask
                    return Activity(healthKitWorkout: workout, heartRate: heartRate, existingID: existingID)
                }
            }
            var activities: [Activity] = []
            activities.reserveCapacity(result.addedSamples.count)
            for try await activity in group {
                activities.append(activity)
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
        return samples.map { HeartRateSample(healthKitQuantitySample: $0) }
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
