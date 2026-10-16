/// What the athlete wants from a generated plan: the generator's soft inputs.
///
/// Preferences are honoured where possible but never override ``PlanGuardrails``. For now this
/// carries only ``runAvailability``; training days, volumes and ramp are
/// added by later tickets (design doc §8.1).
public struct PlanPreferences: Sendable, Codable, Hashable {
    /// When the athlete can run. Seeded from the athlete's global availability setting, which does
    /// not depend on any plan or on the training paradigm. Defaults to no availability.
    public var runAvailability: RunAvailability

    /// Creates plan preferences.
    ///
    /// - Parameter runAvailability: When the athlete can run. Defaults to no availability.
    public init(runAvailability: RunAvailability = RunAvailability()) {
        self.runAvailability = runAvailability
    }

    private enum CodingKeys: String, CodingKey {
        case runAvailability
    }

    /// Decodes preferences, falling back to the default for any missing field so a payload written
    /// before a field existed still decodes.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        runAvailability = try container.decodeIfPresent(RunAvailability.self, forKey: .runAvailability) ?? RunAvailability()
    }
}
