/// The kind of run an athlete wants on a day of a micro-cycle, one element of
/// ``PlanPreferences/dayRunTypes``.
///
/// A run type is what the athlete chooses; it maps onto the physiological ``IntensityCategory``
/// (``intensityCategory``) and onto the generic ``SessionType`` the library's workouts are tagged
/// with (``sessionType``). The mapping:
///
/// | Run type | ``IntensityCategory`` | ``SessionType`` |
/// |---|---|---|
/// | ``recovery`` | ``IntensityCategory/veryLow`` | ``SessionType/recovery`` |
/// | ``easy`` | ``IntensityCategory/low`` | ``SessionType/easy`` |
/// | ``long`` | ``IntensityCategory/low`` | ``SessionType/long`` |
/// | ``threshold`` | ``IntensityCategory/high`` | ``SessionType/tempo`` |
/// | ``interval`` | ``IntensityCategory/high`` | ``SessionType/interval`` |
public enum RunType: String, Sendable, Codable, Hashable, CaseIterable {
    /// A very easy run, essentially all in zone 1.
    case recovery
    /// A comfortable aerobic run.
    case easy
    /// The long run of the micro.
    case long
    /// A sustained effort at threshold.
    case threshold
    /// Repeated hard efforts with recoveries.
    case interval

    /// The intensity category a run of this type falls in.
    public var intensityCategory: IntensityCategory {
        switch self {
        case .recovery: .veryLow
        case .easy, .long: .low
        case .threshold, .interval: .high
        }
    }

    /// The generic session type used to find library workouts for this run type.
    public var sessionType: SessionType {
        switch self {
        case .recovery: .recovery
        case .easy: .easy
        case .long: .long
        case .threshold: .tempo
        case .interval: .interval
        }
    }

    /// The run types allowed on a micro day for which the athlete has not chosen any: only the
    /// easy ones, ``recovery`` and ``easy`` (zones 1 and 2). Quality and long runs happen only on
    /// days the athlete names them.
    public static let defaultForUnspecifiedDay: Set<RunType> = [.recovery, .easy]
}
