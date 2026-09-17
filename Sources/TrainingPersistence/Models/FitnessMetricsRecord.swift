import TrainingCore
import Foundation
import SwiftData

/// The persisted row for one cached, **final** day of ``FitnessMetrics`` — see
/// ``FitnessMetricsCacheStore``'s doc comment for what "final" means here.
///
/// Follows ``ActivityRecord``'s convention: a couple of queryable columns plus a single
/// JSON-encoded `payload`, rather than one attribute per `FitnessMetrics` field. `load` is broken
/// out (not just `day`) so `SwiftDataStore.recentLoads(before:count:)` never has to decode the full
/// payload just to read one `Double`.
///
/// Every stored property has a default value, and none is `@Attribute(.unique)`, for the same
/// CloudKit-`ModelConfiguration` compatibility reason as ``ActivityRecord``. Uniqueness-by-`day` is
/// enforced by ``SwiftDataStore``, which looks a record up by `day` before deciding whether to
/// update it or insert a new one.
@Model
public final class FitnessMetricsRecord {
    /// Mirrors `FitnessMetrics.day`.
    public var day: Date = Date(timeIntervalSince1970: 0)
    /// Mirrors `FitnessMetrics.load`.
    var load: Double = 0
    /// The JSON-encoded `FitnessMetrics`.
    var payload: Data = Data()

    init(day: Date, load: Double, payload: Data) {
        self.day = day
        self.load = load
        self.payload = payload
    }
}

extension FitnessMetricsRecord {
    /// Creates a fitness-metrics record by encoding `metrics`.
    ///
    /// - Parameter metrics: The day's metrics to persist.
    public convenience init(metrics: FitnessMetrics) throws {
        self.init(day: metrics.day, load: metrics.load, payload: try PersistenceCoding.encode(metrics))
    }

    /// Decodes `payload` back into a `FitnessMetrics`.
    public func toMetrics() throws -> FitnessMetrics {
        try PersistenceCoding.decode(FitnessMetrics.self, from: payload)
    }

    /// Replaces this record's `load`/`payload` with `metrics`'s, leaving `day` unchanged.
    ///
    /// - Parameter metrics: The day's metrics to update this record from.
    public func update(from metrics: FitnessMetrics) throws {
        load = metrics.load
        payload = try PersistenceCoding.encode(metrics)
    }
}
