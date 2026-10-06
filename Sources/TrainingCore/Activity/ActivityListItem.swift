import Foundation

/// What a list of activities shows: an ``Activity`` without its samples and statistics.
///
/// Not to be confused with the display-oriented ``ActivitySummary``.
///
/// The persistence layer decodes these fields from the same encoded payload as ``Activity``, so
/// renaming or re-keying one of them in `Activity`'s `Codable` conformance must be mirrored there.
///
/// Read through ``ActivityStore/activityListItems(in:)``, which a store can answer without building
/// every activity's heart-rate and speed samples; fetch the full ``Activity`` with
/// ``ActivityStore/activity(id:)`` when one is opened.
public struct ActivityListItem: Identifiable, Sendable, Hashable {
    /// The activity's ``Activity/id``.
    public let id: UUID
    /// The kind of activity performed.
    public var sport: Sport
    /// When the activity began.
    public var start: Date
    /// How long the activity lasted.
    public var duration: TimeInterval
    /// Total distance covered, if the source/sport reports one.
    public var distanceMeters: Double?
    /// The plan this activity is matched to, if any (``Activity/linkedPlanID``).
    public var linkedPlanID: UUID?

    /// Creates a list item.
    ///
    /// - Parameters:
    ///   - id: The activity's id.
    ///   - sport: The kind of activity performed.
    ///   - start: When the activity began.
    ///   - duration: How long it lasted, in seconds.
    ///   - distanceMeters: Total distance in meters, if known.
    ///   - linkedPlanID: The matched plan's id, if any.
    public init(
        id: UUID, sport: Sport, start: Date, duration: TimeInterval,
        distanceMeters: Double? = nil, linkedPlanID: UUID? = nil
    ) {
        self.id = id
        self.sport = sport
        self.start = start
        self.duration = duration
        self.distanceMeters = distanceMeters
        self.linkedPlanID = linkedPlanID
    }

    /// The list item for `activity`.
    ///
    /// - Parameter activity: The activity to read the list fields from.
    public init(_ activity: Activity) {
        self.init(
            id: activity.id, sport: activity.sport, start: activity.start, duration: activity.duration,
            distanceMeters: activity.distanceMeters, linkedPlanID: activity.linkedPlanID
        )
    }
}
