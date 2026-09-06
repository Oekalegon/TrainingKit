import TrainingCore
import Foundation
import SwiftData

/// The persisted row for a completed `Activity`.
///
/// Every field beyond `id` and `sourceKey` (needed to look a record up by id or by
/// `ActivitySource`) is a single JSON-encoded `payload` rather than one SwiftData attribute per
/// `Activity` field — `Activity` is already `Codable` and round-trips exactly, and exploding every
/// nested type (`HeartRateSample`, `SpeedSample`, `ElevationStats`, ...) into its own attributes or
/// relationships would multiply the schema for no query benefit MVP 1 actually needs.
///
/// Every stored property has a default value, and none is `@Attribute(.unique)` — both required
/// for a SwiftData model to be usable in a CloudKit-backed `ModelConfiguration`. Uniqueness-by-id
/// is instead enforced by ``SwiftDataStore``, which always looks a record up by `id` before
/// deciding whether to update it or insert a new one.
///
/// Public so a host app can include it in a `Schema`/`ModelContainer` of its own composition
/// (alongside its own models, or with a different `ModelConfiguration`) rather than being
/// restricted to ``TrainingPersistenceContainer``'s.
@Model
public final class ActivityRecord {
    /// Mirrors `Activity.id`.
    public var id: UUID = UUID()
    /// A stable string key derived from `Activity.source`, so
    /// `ActivityStore.activity(source:)`/`deleteActivity(source:)` can look a record up without
    /// decoding `payload`.
    public var sourceKey: String = ""
    /// The JSON-encoded `Activity`.
    public var payload: Data = Data()

    /// Creates an activity record directly from its stored fields.
    ///
    /// - Parameters:
    ///   - id: Mirrors `Activity.id`.
    ///   - sourceKey: A stable string key derived from `Activity.source`.
    ///   - payload: The JSON-encoded `Activity`.
    public init(id: UUID, sourceKey: String, payload: Data) {
        self.id = id
        self.sourceKey = sourceKey
        self.payload = payload
    }
}

extension ActivityRecord {
    /// Creates an activity record by encoding `activity`.
    ///
    /// - Parameter activity: The activity to persist.
    public convenience init(activity: Activity) throws {
        self.init(id: activity.id, sourceKey: activity.source.persistenceKey, payload: try PersistenceCoding.encode(activity))
    }

    /// Decodes `payload` back into an `Activity`.
    public func toActivity() throws -> Activity {
        try PersistenceCoding.decode(Activity.self, from: payload)
    }

    /// Replaces this record's `sourceKey`/`payload` with `activity`'s, leaving `id` unchanged.
    ///
    /// - Parameter activity: The activity to update this record from.
    public func update(from activity: Activity) throws {
        sourceKey = activity.source.persistenceKey
        payload = try PersistenceCoding.encode(activity)
    }
}
