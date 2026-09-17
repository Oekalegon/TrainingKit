/// Computes a ``TrainingLoad`` for a completed ``Activity``.
///
/// Multiple calculators can be tried in order (e.g. by ``DailyLoadSeries``) so an activity
/// without heart-rate data falls back to a duration/RPE-based calculator instead of scoring 0.
public protocol LoadCalculator: Sendable {
    func load(for activity: Activity, athlete: AthleteProfile) throws(LoadError) -> TrainingLoad
}
