import Foundation

/// Distance covered over time, integrated from an ``Activity/speed`` stream — used by
/// ``PaceHistory`` to find how far an activity went in a stretch of time and when it reached a
/// distance.
struct DistanceTrack: Sendable {
    /// A stretch between two consecutive speed samples.
    struct Segment: Sendable {
        let start: Date
        let seconds: Double
        let meters: Double
    }

    /// Each sample's time and the meters covered up to it.
    private let times: [Date]
    private let cumulativeMeters: [Double]
    /// The stretches that count as moving: every pair of consecutive samples no further apart than
    /// the gap threshold.
    let segments: [Segment]

    /// Integrates `speed` (sorted by time) with the trapezoid rule; a gap longer than
    /// `gapThresholdSeconds` adds no distance.
    init(speed: [SpeedSample], gapThresholdSeconds: TimeInterval) {
        var times: [Date] = []
        var cumulative: [Double] = []
        var segments: [Segment] = []
        var total = 0.0
        for (index, sample) in speed.enumerated() {
            if index > 0 {
                let previous = speed[index - 1]
                let seconds = sample.time.timeIntervalSince(previous.time)
                if seconds > 0, seconds <= gapThresholdSeconds {
                    let meters = max(0, (previous.metersPerSecond + sample.metersPerSecond) / 2 * seconds)
                    total += meters
                    segments.append(Segment(start: previous.time, seconds: seconds, meters: meters))
                }
            }
            times.append(sample.time)
            cumulative.append(total)
        }
        self.times = times
        self.cumulativeMeters = cumulative
        self.segments = segments
    }

    /// Meters covered over the whole stream.
    var totalMeters: Double { cumulativeMeters.last ?? 0 }

    /// Meters covered by `time`, interpolated between samples and clamped to the stream's ends.
    func meters(at time: Date) -> Double {
        guard let first = times.first, let last = times.last else { return 0 }
        if time <= first { return 0 }
        if time >= last { return totalMeters }
        var low = 0
        var high = times.count - 1
        while high - low > 1 {
            let mid = (low + high) / 2
            if times[mid] <= time { low = mid } else { high = mid }
        }
        let span = times[high].timeIntervalSince(times[low])
        guard span > 0 else { return cumulativeMeters[high] }
        let fraction = time.timeIntervalSince(times[low]) / span
        return cumulativeMeters[low] + (cumulativeMeters[high] - cumulativeMeters[low]) * fraction
    }

    /// When the distance covered first reaches `meters`, or `nil` if it never does.
    func time(reaching meters: Double) -> Date? {
        guard let index = cumulativeMeters.firstIndex(where: { $0 >= meters }) else { return nil }
        guard index > 0 else { return times[0] }
        let previous = cumulativeMeters[index - 1]
        let gained = cumulativeMeters[index] - previous
        guard gained > 0 else { return times[index] }
        let fraction = (meters - previous) / gained
        return times[index - 1].addingTimeInterval(times[index].timeIntervalSince(times[index - 1]) * fraction)
    }
}
