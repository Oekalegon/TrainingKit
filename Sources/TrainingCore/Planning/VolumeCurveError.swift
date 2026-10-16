/// Why ``VolumeCurveBuilder`` could not build a curve.
public enum VolumeCurveError: Error, Sendable, Hashable {
    /// The starting and peak volume are in different ``VolumeMeasure``s.
    case mismatchedMeasure
    /// The peak volume is below the starting volume, so the build micros could not climb to it.
    case peakBelowStart
    /// A fraction of the builder is not a positive, finite number.
    case invalidFraction
}
