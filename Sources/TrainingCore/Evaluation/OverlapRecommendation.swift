import Foundation

/// What ``ActivityOverlapChecker`` advises doing about a pair of activities whose time ranges
/// overlap, or sit close enough together to matter.
public enum OverlapRecommendation: Sendable, Hashable {
    /// The two activities cover the same time span (within
    /// ``ActivityOverlapThresholds/sameSessionTolerance``), the same sport, and identical data —
    /// almost certainly the same workout logged twice. `remove` is safe to delete without asking.
    /// `keep` is whichever of the pair already has a ``Activity/linkedPlanID`` (dropping that copy
    /// would silently lose the ``PlanReconciler`` match), or — when both or neither are linked —
    /// whichever carries the richer data (more HR/speed samples, distance, elevation, cadence,
    /// geographic bounds, perceived exertion), with ties broken arbitrarily since the data is
    /// identical either way.
    case duplicate(keep: UUID, remove: UUID)
    /// The two activities cover the same time span and sport, but their data differs (e.g. one
    /// has HR data the other doesn't, or a different recorded distance) — likely the same session
    /// logged from two sources. Ask the user which fields to keep from which source; a plain
    /// "delete one" should also be offered as a fallback to merging.
    case merge
    /// The two activities are the same sport family and back-to-back, separated by no more than
    /// ``ActivityOverlapThresholds/joinGapTolerance`` — almost certainly one session that was
    /// accidentally stopped and restarted. Offer to combine them into a single activity
    /// (``TrainingModel/joinActivities(_:_:asOf:)``) rather than treating them as a multisport
    /// pairing. The join is reversible (``TrainingModel/unjoinActivity(id:asOf:)``): the originals
    /// stay stored and are only hidden behind the joined activity.
    case join
    /// The two activities overlap with a different start/end (beyond tolerance) or a different
    /// sport — likely two separate logging attempts at one real activity rather than two real
    /// activities. Ask the user which one actually happened and delete the other.
    case conflict
    /// One activity's range fully contains the other's, or the two are close enough
    /// (``ActivityOverlapThresholds/multisportGapTolerance``) to be back-to-back legs — likely a
    /// multisport session (e.g. a triathlon logged as a summary activity plus its swim/bike/run
    /// legs, or two activities logged separately for each leg). Suggest keeping both and linking
    /// them, rather than treating this as a conflict.
    case possibleMultisport
}
