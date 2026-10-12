import Foundation

extension Array where Element == SpeedSample {
    /// The samples averaged over consecutive windows of `seconds`, one sample per window that has any.
    ///
    /// A Watch records running speed every second or so; an hour-long run is thousands of samples that
    /// ``DistanceTrack`` and the pace chart gain nothing from, and that every stored activity would
    /// carry. A window's sample sits at the mean of its times and holds the mean of its speeds, so the
    /// distance integrated from the result stays close to the original's, and a pause (a window with
    /// no samples) stays a gap.
    ///
    /// - Parameter seconds: The window length; a value of zero or less returns the samples unchanged.
    /// - Returns: The averaged samples in time order, from windows counted from the earliest sample.
    public func downsampled(everySeconds seconds: TimeInterval) -> [SpeedSample] {
        guard seconds > 0, count > 1 else { return self }
        let sorted = self.sorted { $0.time < $1.time }
        let origin = sorted[0].time
        var result: [SpeedSample] = []
        var window = 0
        var times = 0.0
        var speeds = 0.0
        var members = 0

        func flush() {
            guard members > 0 else { return }
            result.append(SpeedSample(
                time: origin.addingTimeInterval(times / Double(members)), metersPerSecond: speeds / Double(members)
            ))
            (times, speeds, members) = (0, 0, 0)
        }
        for sample in sorted {
            let index = Int(sample.time.timeIntervalSince(origin) / seconds)
            if index != window {
                flush()
                window = index
            }
            times += sample.time.timeIntervalSince(origin)
            speeds += sample.metersPerSecond
            members += 1
        }
        flush()
        return result
    }
}
