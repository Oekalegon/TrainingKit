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
/// - `Activity.source = .healthKit(workout.uuid)` — that UUID is the dedupe key, matching
///   `ActivityStore.activity(source:)`.
public struct HealthKitActivityImporter: ActivityImporting {
    private let healthStore: HKHealthStore

    /// Creates a HealthKit activity importer.
    ///
    /// - Parameter healthStore: The health store to import from; the caller is responsible for
    ///   requesting authorization first (see ``HealthKitAuthorization``).
    public init(healthStore: HKHealthStore) {
        self.healthStore = healthStore
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

        var activities: [Activity] = []
        activities.reserveCapacity(result.addedSamples.count)
        for workout in result.addedSamples {
            let heartRate = try await heartRateSamples(for: workout)
            activities.append(Activity(healthKitWorkout: workout, heartRate: heartRate))
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
