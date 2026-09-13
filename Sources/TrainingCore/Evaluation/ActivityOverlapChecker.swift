import Foundation

/// Classifies what to do about activities whose ``Activity/dateRange``s overlap or sit close
/// together, rather than just flagging that they do.
///
/// Four outcomes, checked in this order for each pair — see ``OverlapRecommendation``:
/// 1. Same time span (within tolerance) and sport, identical data → ``OverlapRecommendation/duplicate(keep:remove:)``.
/// 2. Same time span and sport, differing data → ``OverlapRecommendation/merge``.
/// 3. Overlapping with a different time span or sport, and neither contains the other →
///    ``OverlapRecommendation/conflict``.
/// 4. One contains the other, or they're merely close together (not overlapping) →
///    ``OverlapRecommendation/possibleMultisport``.
public enum ActivityOverlapChecker {
    /// Finds every pair of `activities` worth advising on: overlapping pairs, plus pairs close
    /// enough together to plausibly be multisport legs.
    ///
    /// - Parameters:
    ///   - activities: The activities to check, in any order.
    ///   - thresholds: The tolerances used to tell a same-session pair from a conflicting one, and
    ///     a multisport transition from two unrelated activities.
    /// - Returns: One ``ActivityOverlapAdvice`` per pair worth surfacing.
    public static func findOverlaps(
        in activities: [Activity],
        thresholds: ActivityOverlapThresholds = ActivityOverlapThresholds()
    ) -> [ActivityOverlapAdvice] {
        var advice: [ActivityOverlapAdvice] = []
        guard activities.count > 1 else { return advice }

        for i in activities.indices {
            for j in activities.indices where j > i {
                let a = activities[i]
                let b = activities[j]
                guard let recommendation = classify(a, b, thresholds: thresholds) else { continue }
                advice.append(ActivityOverlapAdvice(first: a.id, second: b.id, recommendation: recommendation))
            }
        }
        return advice
    }

    private static func classify(
        _ a: Activity, _ b: Activity, thresholds: ActivityOverlapThresholds
    ) -> OverlapRecommendation? {
        let overlapStart = max(a.dateRange.lowerBound, b.dateRange.lowerBound)
        let overlapEnd = min(a.dateRange.upperBound, b.dateRange.upperBound)

        guard overlapStart < overlapEnd else {
            // Not overlapping — still worth flagging if the gap between them is small enough to
            // read as a multisport transition (e.g. T1/T2), in either order.
            let gap = a.dateRange.upperBound <= b.dateRange.lowerBound
                ? b.dateRange.lowerBound.timeIntervalSince(a.dateRange.upperBound)
                : a.dateRange.lowerBound.timeIntervalSince(b.dateRange.upperBound)
            return gap <= thresholds.multisportGapTolerance ? .possibleMultisport : nil
        }

        let sameSession = a.sport == b.sport
            && abs(a.dateRange.lowerBound.timeIntervalSince(b.dateRange.lowerBound)) <= thresholds.sameSessionTolerance
            && abs(a.dateRange.upperBound.timeIntervalSince(b.dateRange.upperBound)) <= thresholds.sameSessionTolerance
        if sameSession {
            return contentMatches(a, b) ? .duplicate(keep: keepID(a, b), remove: removeID(a, b)) : .merge
        }

        // Exact-range equality doesn't count as containment: two entries spanning the identical
        // instant with a different sport read as one activity mislabeled twice (a conflict), not
        // a parent activity containing a shorter child leg.
        let sameRange = a.dateRange.lowerBound == b.dateRange.lowerBound && a.dateRange.upperBound == b.dateRange.upperBound
        guard !sameRange else { return .conflict }

        let aContainsB = a.dateRange.lowerBound <= b.dateRange.lowerBound && b.dateRange.upperBound <= a.dateRange.upperBound
        let bContainsA = b.dateRange.lowerBound <= a.dateRange.lowerBound && a.dateRange.upperBound <= b.dateRange.upperBound
        return aContainsB || bContainsA ? .possibleMultisport : .conflict
    }

    /// Whether `a` and `b` carry identical data beyond the ``Activity/id``, ``Activity/source``,
    /// and ``Activity/linkedPlanID`` fields that necessarily differ between two logged copies of
    /// the same activity. `sport` isn't checked here — the caller has already confirmed it matches
    /// before calling this.
    private static func contentMatches(_ a: Activity, _ b: Activity) -> Bool {
        a.distanceMeters == b.distanceMeters
            && a.heartRate == b.heartRate
            && a.speed == b.speed
            && a.elevation == b.elevation
            && a.cadence == b.cadence
            && a.geographicBounds == b.geographicBounds
            && a.perceivedExertion == b.perceivedExertion
    }

    /// How much data `activity` carries — used to pick which of two duplicate activities to keep.
    private static func richness(_ activity: Activity) -> Int {
        var score = 0
        if !activity.heartRate.isEmpty { score += 1 }
        if !activity.speed.isEmpty { score += 1 }
        if activity.distanceMeters != nil { score += 1 }
        if activity.elevation != nil { score += 1 }
        if activity.cadence != nil { score += 1 }
        if activity.geographicBounds != nil { score += 1 }
        if activity.perceivedExertion != nil { score += 1 }
        return score
    }

    private static func keepID(_ a: Activity, _ b: Activity) -> UUID {
        richness(a) >= richness(b) ? a.id : b.id
    }

    private static func removeID(_ a: Activity, _ b: Activity) -> UUID {
        richness(a) >= richness(b) ? b.id : a.id
    }
}
