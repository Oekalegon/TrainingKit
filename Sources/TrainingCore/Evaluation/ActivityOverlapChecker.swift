import Foundation

/// Flags activities whose ``Activity/dateRange``s overlap in a way that looks like a logging
/// mistake (e.g. the same workout imported twice from different sources) rather than expected
/// containment (e.g. a triathlon leg logged as its own activity nested inside a multisport-watch
/// summary activity).
public enum ActivityOverlapChecker {
    /// Finds every pair of `activities` that overlap without one fully containing the other.
    ///
    /// Containment is inferred purely from ``Activity/dateRange`` — one activity's range lying
    /// entirely inside another's — since `Activity` doesn't model a parent/sub-activity
    /// relationship. A contained pair is excluded even when it shares no other detail (sport,
    /// source): it reads as a summary activity with a leg logged separately, not a duplicate or
    /// scheduling conflict.
    ///
    /// - Parameter activities: The activities to check, in any order.
    /// - Returns: One ``ActivityOverlap`` per overlapping, non-contained pair.
    public static func findOverlaps(in activities: [Activity]) -> [ActivityOverlap] {
        var overlaps: [ActivityOverlap] = []
        guard activities.count > 1 else { return overlaps }

        for i in activities.indices {
            for j in activities.indices where j > i {
                let a = activities[i]
                let b = activities[j]

                // A plain `ClosedRange.overlaps` check would flag back-to-back activities that
                // merely touch at a shared instant (one ending exactly as the next begins) — not
                // a real conflict, so overlap requires a positive-duration intersection instead.
                let overlapStart = max(a.dateRange.lowerBound, b.dateRange.lowerBound)
                let overlapEnd = min(a.dateRange.upperBound, b.dateRange.upperBound)
                guard overlapStart < overlapEnd else { continue }

                let isContained = a.dateRange.lowerBound <= b.dateRange.lowerBound
                    && b.dateRange.upperBound <= a.dateRange.upperBound
                    || b.dateRange.lowerBound <= a.dateRange.lowerBound
                    && a.dateRange.upperBound <= b.dateRange.upperBound
                guard !isContained else { continue }

                overlaps.append(
                    ActivityOverlap(first: a.id, second: b.id, overlappingRange: overlapStart...overlapEnd)
                )
            }
        }
        return overlaps
    }
}
