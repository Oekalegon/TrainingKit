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
    /// The largest gap between one activity's end and the next activity's start — or, equally, the
    /// largest overlap between them — for two same-sport-family activities that still reads as one
    /// session accidentally recorded in two pieces (e.g. a watch workout stopped and immediately
    /// restarted) rather than two runs.
    ///
    /// The joined activity's duration spans the gap (see ``Activity/joined(_:_:)``), so a larger
    /// tolerance means a join can add up to that much idle time to a session whose load falls
    /// back to duration × RPE; heart-rate TRIMP is unaffected, since it skips gaps over 60 s.
    public var joinGapTolerance: TimeInterval

    /// Creates activity-overlap thresholds.
    ///
    /// - Parameters:
    ///   - sameSessionTolerance: Start/end tolerance for treating an overlapping pair as the same
    ///     session; defaults to 5 minutes.
    ///   - multisportGapTolerance: The largest gap between adjacent activities that still suggests
    ///     multisport legs; defaults to 30 minutes.
    ///   - joinGapTolerance: The largest gap between two same-sport activities that still suggests
    ///     one session split in two; defaults to 5 minutes.
    public init(
        sameSessionTolerance: TimeInterval = 5 * 60,
        multisportGapTolerance: TimeInterval = 30 * 60,
        joinGapTolerance: TimeInterval = 5 * 60
    ) {
        self.sameSessionTolerance = sameSessionTolerance
        self.multisportGapTolerance = multisportGapTolerance
        self.joinGapTolerance = joinGapTolerance
    }

    private enum CodingKeys: String, CodingKey {
        case sameSessionTolerance, multisportGapTolerance, joinGapTolerance
    }

    /// Decodes thresholds, falling back to the default for ``joinGapTolerance`` when it's absent —
    /// so a value encoded before that field existed still decodes.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ActivityOverlapThresholds()
        sameSessionTolerance = try container.decode(TimeInterval.self, forKey: .sameSessionTolerance)
        multisportGapTolerance = try container.decode(TimeInterval.self, forKey: .multisportGapTolerance)
        joinGapTolerance = try container.decodeIfPresent(TimeInterval.self, forKey: .joinGapTolerance)
            ?? defaults.joinGapTolerance
    }
}
