/// Computes training load from duration and rating of perceived exertion (session-RPE), for
/// activities without heart-rate data — most commonly strength training.
public struct DurationRPECalculator: LoadCalculator {
    /// Creates a duration/RPE load calculator.
    public init() {}

    /// Computes the load as duration in minutes multiplied by rating of perceived exertion.
    ///
    /// - Parameters:
    ///   - activity: The activity to score; must have `perceivedExertion` set.
    ///   - athlete: Unused by this calculator, present to satisfy ``LoadCalculator``.
    /// - Returns: A ``TrainingLoad`` with `method: .durationRPE` and full confidence.
    /// - Throws: ``LoadError/missingPerceivedExertion`` if `activity.perceivedExertion` is `nil`.
    public func load(for activity: Activity, athlete: AthleteProfile) throws(LoadError) -> TrainingLoad {
        guard let rpe = activity.perceivedExertion else {
            throw LoadError.missingPerceivedExertion
        }
        let durationMinutes = activity.duration / 60
        return TrainingLoad(value: durationMinutes * Double(rpe), method: .durationRPE, confidence: 1.0)
    }
}
