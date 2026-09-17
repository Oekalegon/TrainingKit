import Foundation

/// Classifies what to do about activities whose ``Activity/dateRange``s overlap or sit close
/// together, rather than just flagging that they do.
///
/// Four outcomes, checked in this order for each pair — see ``OverlapRecommendation``:
/// 1. Same time span (within tolerance) and sport family (``Sport/isSameFamily(as:)``), identical
///    data → ``OverlapRecommendation/duplicate(keep:remove:)``.
/// 2. Same time span and sport family, differing data → ``OverlapRecommendation/merge``.
/// 3. Overlapping with a different time span or sport family, and neither contains the other →
///    ``OverlapRecommendation/conflict``.
/// 4. One contains the other, or they're merely close together (not overlapping) →
///    ``OverlapRecommendation/possibleMultisport``.
public enum ActivityOverlapChecker {
    /// Finds every pair of `activities` worth advising on: overlapping pairs, plus pairs close
    /// enough together to plausibly be multisport legs.
    ///
    /// Sorts `activities` by start once, then for each activity only scans forward while a later
    /// activity's start still falls within `thresholds.multisportGapTolerance` of its own end —
    /// beyond that, no later activity (also sorted by start) can overlap or be close enough to
    /// matter, so the scan stops early instead of comparing every pair. This keeps the common case
    /// (activities spread across weeks/months, each only near a handful of others) far cheaper than
    /// the full O(n²) pair count would suggest; only an activity spanning an unusually long
    /// duration forces a longer inner scan, and only for that one activity.
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

        let sorted = activities.sorted { $0.dateRange.lowerBound < $1.dateRange.lowerBound }
        for i in sorted.indices {
            let a = sorted[i]
            let reach = a.dateRange.upperBound.addingTimeInterval(thresholds.multisportGapTolerance)
            for j in (i + 1)..<sorted.count {
                let b = sorted[j]
                guard b.dateRange.lowerBound <= reach else { break }
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

        let sameSession = a.sport.isSameFamily(as: b.sport)
            && abs(a.dateRange.lowerBound.timeIntervalSince(b.dateRange.lowerBound)) <= thresholds.sameSessionTolerance
            && abs(a.dateRange.upperBound.timeIntervalSince(b.dateRange.upperBound)) <= thresholds.sameSessionTolerance
        if sameSession {
            guard contentMatches(a, b) else { return .merge }
            let (keep, remove) = keepAndRemove(a, b)
            return .duplicate(keep: keep, remove: remove)
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

    /// Which of two duplicate activities to keep: whichever already carries a
    /// ``Activity/linkedPlanID`` wins outright, since discarding it would silently drop that
    /// ``PlanReconciler`` match — the one field ``contentMatches(_:_:)`` deliberately doesn't
    /// require to be equal. Only when both or neither are linked does richness decide.
    private static func keepAndRemove(_ a: Activity, _ b: Activity) -> (keep: UUID, remove: UUID) {
        if (a.linkedPlanID != nil) != (b.linkedPlanID != nil) {
            return a.linkedPlanID != nil ? (a.id, b.id) : (b.id, a.id)
        }
        return richness(a) >= richness(b) ? (a.id, b.id) : (b.id, a.id)
    }
}
