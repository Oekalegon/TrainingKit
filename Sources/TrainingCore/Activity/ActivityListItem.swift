import Foundation

/// What a list of activities shows: an ``Activity`` without its samples and statistics (distinct from the display-oriented ``ActivitySummary``).
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

    /// Creates a summary.
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

    /// The summary of `activity`.
    public init(_ activity: Activity) {
        self.init(
            id: activity.id, sport: activity.sport, start: activity.start, duration: activity.duration,
            distanceMeters: activity.distanceMeters, linkedPlanID: activity.linkedPlanID
        )
    }
}
