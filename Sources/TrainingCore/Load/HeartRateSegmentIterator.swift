import Foundation

/// Splits a heart-rate sample stream into consecutive trapezoid segments, applying the shared gap
/// rule: a segment between two samples further apart than `gapThresholdSeconds` is treated as a
/// pause and dropped rather than bridged.
///
/// Shared by ``ExponentialTRIMPCalculator`` and the time-in-zone calculation in
/// `TrainingCore/Statistics/`, so zone seconds and TRIMP always agree on what counts as "in the
/// activity".
public struct HeartRateSegmentIterator: Sendable {
    /// Gaps between consecutive samples longer than this are treated as a pause and skipped.
    public var gapThresholdSeconds: TimeInterval
    /// Converts each sample's bpm into a heart-rate-reserve ratio.
    public var zoneModel: HeartRateZoneModel

    /// Creates a heart-rate segment iterator.
    ///
    /// - Parameters:
    ///   - gapThresholdSeconds: Gaps longer than this are treated as a pause and skipped.
    ///   - zoneModel: Converts each sample's bpm into a heart-rate-reserve ratio.
    public init(gapThresholdSeconds: TimeInterval, zoneModel: HeartRateZoneModel) {
        self.gapThresholdSeconds = gapThresholdSeconds
        self.zoneModel = zoneModel
    }

    /// One trapezoid segment between two consecutive, non-gap samples.
    public struct Segment: Sendable {
        /// Elapsed time between the two samples, in seconds.
        public let duration: TimeInterval
        /// The heart-rate-reserve ratio at the start of the segment.
        public let startRatio: Double
        /// The heart-rate-reserve ratio at the end of the segment.
        public let endRatio: Double
        /// The average of `startRatio` and `endRatio`, used by the trapezoidal TRIMP integration.
        public var averageRatio: Double { (startRatio + endRatio) / 2 }
    }

    /// The non-gap segments between consecutive samples, sorted by time.
    public func segments(samples: [HeartRateSample]) -> [Segment] {
        let sorted = samples.sorted { $0.time < $1.time }
        var result: [Segment] = []
        for (previous, current) in zip(sorted, sorted.dropFirst()) {
            let dt = current.time.timeIntervalSince(previous.time)
            guard dt > 0, dt <= gapThresholdSeconds else { continue }
            result.append(
                Segment(
                    duration: dt,
                    startRatio: zoneModel.deltaHRRatio(for: previous.bpm),
                    endRatio: zoneModel.deltaHRRatio(for: current.bpm)
                )
            )
        }
        return result
    }
}
