/// Why ``StepTargetResolver`` could not give a step the target it was asked for.
public enum UnresolvedReason: Sendable, Codable, Hashable {
    /// The athlete has no heart-rate zone settings, so a zone target has no bpm range.
    case noHeartRateZones
    /// The step's zone has no bpm range under the athlete's zone method: it is outside 1...5, or the
    /// method is lactate threshold and no threshold heart rate is set. Carries the zone.
    case zoneUnavailable(Int)
    /// The phase asks for a fraction of the race target but there is no race target.
    case noRaceTarget
    /// The step asks for the phase's intensity (``IntensityTarget/phaseIntensity``) but the plan's phase gives no
    /// fraction of the race pace for it (MVP5-153): the template does not suit this profile.
    case noPhaseFraction
    /// The race target is not a pace (a heart rate, an effort or a prediction), so a fraction of it
    /// cannot be turned into a pace.
    case unsupportedRaceTarget
    /// The pace the phase asks for is not a pace of the step's zone: the template is the wrong
    /// workout for this phase. Carries the step's zone and the zone the phase pace falls in
    /// (`nil` when it is faster or slower than every zone). The step keeps its zone's own pace.
    case paceOutsideZone(zone: Int, paceZone: Int?)
}
