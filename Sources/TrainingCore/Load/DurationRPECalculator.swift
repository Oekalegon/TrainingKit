/// Computes training load from duration and rating of perceived exertion (session-RPE), for
/// activities without heart-rate data — most commonly strength training.
public struct DurationRPECalculator: LoadCalculator {
    public init() {}

    public func load(for activity: Activity, athlete: AthleteProfile) throws(LoadError) -> TrainingLoad {
        guard let rpe = activity.perceivedExertion else {
            throw LoadError.missingPerceivedExertion
        }
        let durationMinutes = activity.duration / 60
        return TrainingLoad(value: durationMinutes * Double(rpe), method: .durationRPE, confidence: 1.0)
    }
}
