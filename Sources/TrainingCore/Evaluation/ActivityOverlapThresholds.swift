import Foundation

/// Tunable thresholds ``ActivityOverlapChecker`` classifies activity pairs against.
public struct ActivityOverlapThresholds: Sendable, Codable, Hashable {
    /// How close two overlapping activities' start times AND end times must each be for them to
    /// be considered the same logged session (a duplicate or merge candidate) rather than two
    /// genuinely different activities that happen to overlap.
    public var sameSessionTolerance: TimeInterval
    /// The largest gap between one activity's end and the next activity's start that still reads
    /// as a transition between legs of one multisport session (e.g. a triathlon's T1/T2) rather
    /// than two unrelated activities.
    public var multisportGapTolerance: TimeInterval

    /// Creates activity-overlap thresholds.
    ///
    /// - Parameters:
    ///   - sameSessionTolerance: Start/end tolerance for treating an overlapping pair as the same
    ///     session; defaults to 5 minutes.
    ///   - multisportGapTolerance: The largest gap between adjacent activities that still suggests
    ///     multisport legs; defaults to 30 minutes.
    public init(sameSessionTolerance: TimeInterval = 5 * 60, multisportGapTolerance: TimeInterval = 30 * 60) {
        self.sameSessionTolerance = sameSessionTolerance
        self.multisportGapTolerance = multisportGapTolerance
    }
}
