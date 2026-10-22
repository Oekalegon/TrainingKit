/// A notice that a paradigm's numbers were calibrated for another race distance than the plan's
/// target race (MVP5-143).
///
/// ``TrainingParadigm/triphasic`` takes its percentages and zone mapping from a marathon table, so a
/// plan for a shorter race gets bands that are too moderate. Example, a 20:00 5K (4:00/km): the base
/// endurance band of 0.80-0.85 of race speed is 4:42-5:00/km, which is moderate, not very easy, for
/// that runner; the warning then carries `raceDistanceMeters` 5,000 and `calibratedDistanceMeters`
/// 42,195. The app formats the text. It is not a ``PlanFinding`` and never makes a proposal
/// unacceptable: see ``PlanProposal/calibrationWarning``.
public struct CalibrationWarning: Sendable, Codable, Hashable {
    /// How far a race distance may be from the calibration distance, as a fraction of it, before the
    /// warning applies: 2 %, so a marathon entered as 42,000 m or 42.5 km does not warn.
    public static let tolerance = 0.02

    /// The distance of the target race, in meters.
    public var raceDistanceMeters: Double
    /// The distance the paradigm is calibrated for, in meters (``TrainingParadigm/calibratedDistanceMeters``).
    public var calibratedDistanceMeters: Double

    /// Creates a warning.
    ///
    /// - Parameters:
    ///   - raceDistanceMeters: The distance of the target race, in meters.
    ///   - calibratedDistanceMeters: The distance the paradigm is calibrated for, in meters.
    public init(raceDistanceMeters: Double, calibratedDistanceMeters: Double) {
        self.raceDistanceMeters = raceDistanceMeters
        self.calibratedDistanceMeters = calibratedDistanceMeters
    }
}
