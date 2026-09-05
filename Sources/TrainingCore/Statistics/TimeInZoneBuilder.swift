import Foundation

/// Builds a ``TimeInZone`` breakdown for a completed activity.
///
/// Shares segments and the gap rule with ``ExponentialTRIMPCalculator`` via
/// ``HeartRateSegmentIterator`` — construct this with the same `gapThresholdSeconds` used for the
/// activity's ``TrainingLoad``, or the two will silently disagree on which segments count as "in
/// the activity". Splits any segment that crosses a zone boundary proportionally by time, rather
/// than assigning it whole to one zone.
struct TimeInZoneBuilder: Sendable {
    /// Gaps between consecutive samples longer than this are excluded, matching
    /// ``ExponentialTRIMPCalculator/gapThresholdSeconds``.
    var gapThresholdSeconds: TimeInterval

    /// Integrates `activity.heartRate` into per-zone seconds using the athlete's zone settings
    /// effective on `activity.start`.
    func timeInZone(for activity: Activity, athlete: AthleteProfile) -> TimeInZone {
        guard let settings = athlete.heartRateZoneSettings(asOf: activity.start) else {
            Logging.statistics.warning("timeInZone(for:athlete:) called with no heartRateZoneHistory recorded for activity \(activity.id, privacy: .public); returning empty")
            return TimeInZone()
        }
        let zoneModel = HeartRateZoneModel(settings: settings)
        guard let boundaries = Self.zoneBoundaries(zoneModel) else { return TimeInZone() }

        let iterator = HeartRateSegmentIterator(gapThresholdSeconds: gapThresholdSeconds, zoneModel: zoneModel)
        var seconds: [Int: TimeInterval] = [:]
        for segment in iterator.segments(samples: activity.heartRate) {
            for (zone, duration) in Self.split(segment, boundaries: boundaries) {
                seconds[zone, default: 0] += duration
            }
        }
        return TimeInZone(seconds: seconds)
    }

    /// Splits one segment's duration across the zone(s) its ratio ramp passes through, by finding
    /// every boundary crossed between `startRatio` and `endRatio` and assigning each sub-interval
    /// to the zone active at its midpoint.
    static func split(_ segment: HeartRateSegmentIterator.Segment, boundaries: [Double]) -> [(zone: Int, duration: TimeInterval)] {
        let r0 = segment.startRatio
        let r1 = segment.endRatio
        guard r0 != r1 else {
            return [(zone(for: r0, boundaries: boundaries), segment.duration)]
        }

        let lower = min(r0, r1)
        let upper = max(r0, r1)
        var crossings = boundaries.filter { $0 > lower && $0 < upper }
        crossings.sort(by: r0 < r1 ? (<) : (>))

        var fractions: [Double] = [0]
        for boundary in crossings {
            fractions.append((boundary - r0) / (r1 - r0))
        }
        fractions.append(1)

        var result: [(zone: Int, duration: TimeInterval)] = []
        for index in 0..<(fractions.count - 1) {
            let start = fractions[index]
            let end = fractions[index + 1]
            let duration = segment.duration * (end - start)
            guard duration > 0 else { continue }
            let midRatio = r0 + (r1 - r0) * (start + end) / 2
            result.append((zone(for: midRatio, boundaries: boundaries), duration))
        }
        return result
    }

    /// Zone edge ratios `[z1.lower, z1.upper, z2.upper, z3.upper, z4.upper, z5.upper]`, or `nil` if
    /// the athlete's zone method can't resolve every zone (e.g. `.lactateThreshold` with no
    /// threshold heart rate recorded).
    static func zoneBoundaries(_ zoneModel: HeartRateZoneModel) -> [Double]? {
        guard let z1 = zoneModel.zoneRatioRange(1),
              let z2 = zoneModel.zoneRatioRange(2),
              let z3 = zoneModel.zoneRatioRange(3),
              let z4 = zoneModel.zoneRatioRange(4),
              let z5 = zoneModel.zoneRatioRange(5)
        else { return nil }
        return [z1.lowerBound, z1.upperBound, z2.upperBound, z3.upperBound, z4.upperBound, z5.upperBound]
    }

    /// The zone number (0...5) whose range contains `ratio`, given the six boundary ratios from
    /// ``zoneBoundaries(_:)``. Ratios at or above the top boundary clamp to zone 5.
    static func zone(for ratio: Double, boundaries: [Double]) -> Int {
        guard ratio >= boundaries[0] else { return 0 }
        for index in 1..<boundaries.count where ratio < boundaries[index] {
            return index
        }
        return 5
    }
}
