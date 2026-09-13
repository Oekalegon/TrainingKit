import Foundation

/// One piece of advice from ``ActivityOverlapChecker/findOverlaps(in:thresholds:)`` about a pair
/// of activities.
public struct ActivityOverlapAdvice: Sendable, Hashable {
    /// One of the two activities' ids.
    public let first: UUID
    /// The other activity's id.
    public let second: UUID
    /// What to do about this pair.
    public let recommendation: OverlapRecommendation

    /// Creates an activity-overlap advice.
    ///
    /// - Parameters:
    ///   - first: One of the two activities' ids.
    ///   - second: The other activity's id.
    ///   - recommendation: What to do about this pair.
    public init(first: UUID, second: UUID, recommendation: OverlapRecommendation) {
        self.first = first
        self.second = second
        self.recommendation = recommendation
    }
}
