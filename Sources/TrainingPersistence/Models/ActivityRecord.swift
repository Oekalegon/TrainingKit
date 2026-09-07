import TrainingCore
import Foundation
import SwiftData

/// The persisted row for a completed `Activity`.
///
/// Every field beyond `id`, `sourceKey` (needed to look a record up by id or by `ActivitySource`),
/// and `start` (needed to filter by date range without decoding `payload`) is a single
/// JSON-encoded `payload` rather than one SwiftData attribute per `Activity` field — `Activity` is
/// already `Codable` and round-trips exactly, and exploding every nested type (`HeartRateSample`,
/// `SpeedSample`, `ElevationStats`, ...) into its own attributes or relationships would multiply
/// the schema for no query benefit MVP 1 actually needs.
///
/// Every stored property has a default value, and none is `@Attribute(.unique)` — both required
/// for a SwiftData model to be usable in a CloudKit-backed `ModelConfiguration`. Uniqueness-by-id
/// is instead enforced by ``SwiftDataStore``, which always looks a record up by `id` before
/// deciding whether to update it or insert a new one.
///
/// The class is public — and `id` with it — so a host app can include it in a `Schema`/
/// `ModelContainer` of its own composition (alongside its own models, or with a different
/// `ModelConfiguration`) rather than being restricted to ``TrainingPersistenceContainer``'s, and
/// run its own lightweight id-based queries against it. `sourceKey` and `payload` stay internal:
/// they're a storage detail of the JSON-blob encoding this file's doc explains above, not a shape
/// external code should read or write directly — ``init(activity:)``/``toActivity()``/
/// ``update(from:)`` are the sanctioned way in and out.
@Model
public final class ActivityRecord {
    /// Mirrors `Activity.id`.
    public var id: UUID = UUID()
    /// A stable string key derived from `Activity.source`, so
    /// `ActivityStore.activity(source:)`/`deleteActivity(source:)` can look a record up without
    /// decoding `payload`.
    var sourceKey: String = ""
    /// Mirrors `Activity.start`, so `ActivityStore.activities(in:)` can filter by date range in
    /// the `FetchDescriptor`'s predicate instead of fetching and decoding every row.
    var start: Date = Date(timeIntervalSince1970: 0)
    /// The JSON-encoded `Activity`.
    var payload: Data = Data()

    init(id: UUID, sourceKey: String, start: Date, payload: Data) {
        self.id = id
        self.sourceKey = sourceKey
        self.start = start
        self.payload = payload
    }
}

extension ActivityRecord {
    /// Creates an activity record by encoding `activity`.
    ///
    /// - Parameter activity: The activity to persist.
    public convenience init(activity: Activity) throws {
        self.init(
            id: activity.id,
            sourceKey: activity.source.persistenceKey,
            start: activity.start,
            payload: try PersistenceCoding.encode(activity)
        )
    }

    /// Decodes `payload` back into an `Activity`.
    public func toActivity() throws -> Activity {
        try PersistenceCoding.decode(Activity.self, from: payload)
    }

    /// Replaces this record's `sourceKey`/`start`/`payload` with `activity`'s, leaving `id`
    /// unchanged.
    ///
    /// - Parameter activity: The activity to update this record from.
    public func update(from activity: Activity) throws {
        sourceKey = activity.source.persistenceKey
        start = activity.start
        payload = try PersistenceCoding.encode(activity)
    }
}
