import Foundation

/// Why a request to join activities (``TrainingModel/joinActivities(_:_:asOf:)``,
/// ``ActivityStore/saveJoin(_:components:replacing:)``) was refused.
public enum ActivityJoinError: Error, Sendable, Hashable {
    /// The activity with this id already belongs to a different join, and that join isn't being
    /// replaced — joining it again would leave two joined activities sharing a piece, so deleting
    /// one of them could take the other's data with it.
    case componentAlreadyJoined(UUID)
    /// The activities aren't all the same sport family (see ``Sport/isSameFamily(as:)``), so they
    /// aren't pieces of one session. ``ActivityOverlapChecker`` only recommends
    /// ``OverlapRecommendation/join`` for same-family pairs; this keeps a direct call honest too.
    case differentSportFamilies
}
