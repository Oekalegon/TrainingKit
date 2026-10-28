import Foundation

/// A reusable, parameterized workout blueprint in the athlete's library, e.g. "Recovery run" with
/// a `duration` parameter, instantiated into a concrete ``StructuredWorkout`` when scheduled.
public struct WorkoutTemplate: Identifiable, Sendable, Codable, Hashable {
    /// A stable identifier for this template.
    public let id: UUID
    /// The template's display name.
    public var name: String
    /// A shorter name for a generated title (``defaultTitle(values:distanceSystem:)``), e.g.
    /// "Hill Sprints" for "Base Full-out hill sprints". `nil` uses `name`.
    public var titleName: String?
    /// The kind of activity this template is for.
    public var sport: Sport
    /// Where the template is done, or `nil` to leave it to the plan. A venue with a surface
    /// (``Venue/outdoor(_:)`` with `.track`) fixes it; one without (`.outdoor(nil)`) fixes only
    /// indoors versus outdoors. See ``venueChoices``.
    public var venue: Venue?
    /// The parameters this template's blocks may reference. Keys must be unique within a
    /// template — a duplicate key silently resolves to whichever entry appears first.
    public var parameters: [WorkoutTemplateParameter]
    /// The ordered blocks making up this template.
    public var blocks: [TemplateBlock]
    /// What workouts made from this template are for; each instantiated ``StructuredWorkout`` gets it
    /// (MVP2-153). Absent from templates saved before this field existed, which decode as
    /// ``WorkoutPurpose/general``.
    public var purpose: WorkoutPurpose
    /// The broad kind of session workouts made from this template are, or `nil` for an untagged
    /// template; each instantiated ``StructuredWorkout`` gets it (MVP5-139). A template tagged
    /// ``SessionType/long`` makes long runs, whatever day they are planned on. Absent from templates
    /// saved before this field existed, which decode as `nil`; an unknown value also reads as `nil`.
    public var sessionType: SessionType?
    /// The days this template's workouts want free of other demanding workouts around them
    /// (MVP5-147), or `nil` for the default of its ``sessionType``: see
    /// ``effectiveRecoveryDays(defaultAfter:longRunsNeedRecovery:)``. Set it for a workout that needs
    /// more (the alternation run wants 1 day before and 3 after) or less than an ordinary intense one.
    /// Absent from templates saved before this field existed, which decode as `nil`.
    public var recoveryDays: RecoveryDays?
    /// When the athlete deleted this template while plans still used it (MVP2-142), or `nil` for one
    /// in use. An archived template stays in the store so those plans can still open its parameters,
    /// but libraries and pickers don't offer it. Absent from templates saved before this field existed.
    public var archivedDate: Date?
    /// Whether the template was archived instead of deleted; see ``archivedDate``.
    public var isArchived: Bool { archivedDate != nil }

    /// Creates a workout template.
    ///
    /// - Parameters:
    ///   - id: A stable identifier; defaults to a new random `UUID`.
    ///   - name: The template's display name.
    ///   - titleName: A shorter name for generated titles; defaults to `nil`, which uses `name`.
    ///   - sport: The kind of activity this template is for.
    ///   - venue: Where the template is done; `nil` leaves it to the plan.
    ///   - parameters: The parameters this template's blocks may reference.
    ///   - blocks: The ordered blocks making up this template.
    ///   - purpose: What workouts made from it are for; defaults to ``WorkoutPurpose/general``.
    ///   - sessionType: The broad kind of session it makes; defaults to `nil` (untagged).
    ///   - recoveryDays: The days it wants free around it; defaults to `nil` (the default of its session type).
    ///   - archivedDate: When the template was archived; defaults to `nil`.
    public init(
        id: UUID = UUID(),
        name: String,
        titleName: String? = nil,
        sport: Sport,
        venue: Venue? = nil,
        parameters: [WorkoutTemplateParameter],
        blocks: [TemplateBlock],
        purpose: WorkoutPurpose = .general,
        sessionType: SessionType? = nil,
        recoveryDays: RecoveryDays? = nil,
        archivedDate: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.titleName = titleName
        self.sport = sport
        self.venue = venue
        self.parameters = parameters
        self.blocks = blocks
        self.purpose = purpose
        self.sessionType = sessionType
        self.recoveryDays = recoveryDays
        self.archivedDate = archivedDate
    }
}

extension WorkoutTemplate {
    /// The days a workout made from this template wants free of other demanding workouts, or `nil`
    /// when it is not demanding (MVP5-147).
    ///
    /// ``recoveryDays`` wins when set. Otherwise the template's ``sessionType`` decides: interval,
    /// tempo and hill sessions are intense and want 0 days before and `defaultAfter` after; a long run
    /// wants the same when `longRunsNeedRecovery` is set (a paradigm that spaces long runs like hard
    /// sessions, and not for an ultra); easy runs, recovery runs and untagged templates want nothing.
    ///
    /// - Parameters:
    ///   - defaultAfter: The days an intense workout wants after it, normally the paradigm's
    ///     ``TrainingParadigm/minDaysBetweenHardSessions``; `nil` for none.
    ///   - longRunsNeedRecovery: Whether a long run counts as intense.
    /// - Returns: The days wanted, or `nil` for a workout that wants nothing on either side.
    public func effectiveRecoveryDays(defaultAfter: Int?, longRunsNeedRecovery: Bool) -> RecoveryDays? {
        if let recoveryDays { return recoveryDays.isNone ? nil : recoveryDays }
        let intense: Bool
        switch sessionType {
        case .interval, .tempo, .hillRepeats: intense = true
        case .long: intense = longRunsNeedRecovery
        default: intense = false
        }
        guard intense, let defaultAfter, defaultAfter > 0 else { return nil }
        return RecoveryDays(before: 0, after: defaultAfter)
    }
}

extension WorkoutTemplate {
    /// The venues a plan editor offers for this template: ``Venue/choices(for:)`` for its sport,
    /// narrowed to those compatible with ``venue`` (and to ``venue`` itself when it names a
    /// surface). Empty for a sport without venue variants.
    public var venueChoices: [Venue] {
        let all = Venue.choices(for: sport)
        guard let venue else { return all }
        if venue.hasSurface { return [venue] }
        return all.filter { Venue.isCompatible(venue, $0) }
    }

    /// Whether the template fixes its venue, so a plan editor hides or locks its venue picker:
    /// there's at most one choice.
    public var isVenueFixed: Bool { venueChoices.count <= 1 }

    /// The venue a plan editor preselects: `preferred` if it's one of ``venueChoices``, else the
    /// first outdoor choice, else the first choice, else the template's own ``venue``.
    ///
    /// - Parameter preferred: The athlete's last or usual choice, if any.
    public func defaultVenue(preferred: Venue? = nil) -> Venue? {
        let choices = venueChoices
        if let preferred, choices.contains(preferred) { return preferred }
        return choices.first { !$0.isIndoor } ?? choices.first ?? venue
    }

    /// The venue a plan editor preselects for `athlete`: their usual venue for the template's sport
    /// (``AthleteProfile/defaultVenue(for:)``) if the template allows it, else ``defaultVenue(preferred:)``'s
    /// own default.
    ///
    /// - Parameter athlete: The athlete planning the workout.
    public func defaultVenue(for athlete: AthleteProfile) -> Venue? {
        defaultVenue(preferred: athlete.defaultVenue(for: sport))
    }

    /// `chosen` if the template allows it, otherwise the template's own ``venue``.
    ///
    /// A venue is allowed when it's one of ``venueChoices`` or compatible with the template's
    /// constraint, so one without a surface (what WorkoutKit, HealthKit and older files give) is kept
    /// for a template that leaves its venue open. A template naming a surface keeps its own.
    private func resolvedVenue(_ chosen: Venue?) -> Venue? {
        guard let chosen else { return venue }
        if venueChoices.contains(chosen) { return chosen }
        guard let venue else { return chosen }
        return !venue.hasSurface && Venue.isCompatible(venue, chosen) ? chosen : venue
    }

    /// Produces a concrete workout by resolving this template's parameters.
    ///
    /// - Parameters:
    ///   - name: The instantiated workout's display name; defaults to this template's name.
    ///   - chosenVenue: The venue to give the workout, chosen from ``venueChoices``; defaults to the
    ///     template's ``venue``. Ignored when the template doesn't allow it (see ``venueChoices``);
    ///     a venue without a surface is kept unless the template names a surface.
    ///   - values: Parameter key to value; a key declared in this template's `parameters` but
    ///     missing from `values` resolves to that parameter's `defaultValue`.
    /// - Returns: A ``StructuredWorkout`` with every ``TemplateValue`` resolved to a fixed value and
    ///   this template's ``purpose``.
    /// - Throws: ``WorkoutTemplateError/undeclaredParameter(_:)`` if a step or block references a
    ///   `.parameter(_:)` key that isn't declared in this template's `parameters` — a typo or a
    ///   stale reference, never something `values` alone can fix.
    public func instantiate(name: String? = nil, venue chosenVenue: Venue? = nil, values: [String: Double] = [:]) throws(WorkoutTemplateError) -> StructuredWorkout {
        func resolve(_ key: String) throws(WorkoutTemplateError) -> Double {
            if let value = values[key] {
                return value
            }
            guard let parameter = parameters.first(where: { $0.key == key }) else {
                throw .undeclaredParameter(key)
            }
            return parameter.defaultValue
        }

        var resolvedBlocks: [WorkoutBlock] = []
        resolvedBlocks.reserveCapacity(blocks.count)
        for block in blocks {
            var steps: [WorkoutStep] = []
            steps.reserveCapacity(block.steps.count)
            for step in block.steps {
                steps.append(WorkoutStep(kind: step.kind, goal: try step.goal.resolve(resolve), target: step.target))
            }
            resolvedBlocks.append(WorkoutBlock(steps: steps, repetitions: try block.repetitions.resolve(resolve)))
        }
        // Every declared parameter's resolved value (an explicit one, else its default), so the
        // workout can later be re-instantiated with a single parameter changed.
        let resolvedValues = Dictionary(uniqueKeysWithValues: parameters.map { ($0.key, values[$0.key] ?? $0.defaultValue) })
        return StructuredWorkout(
            name: name ?? self.name, sport: sport, venue: resolvedVenue(chosenVenue), blocks: resolvedBlocks,
            templateID: id, parameterValues: resolvedValues, purpose: purpose, sessionType: sessionType
        )
    }

    /// The estimated training load `instantiate(values:)` would produce, without building the
    /// intermediate `StructuredWorkout` by hand.
    ///
    /// - Parameters:
    ///   - values: Parameter key to value, as passed to `instantiate(values:)`.
    ///   - estimator: Estimates load from a step's target intensity in place of measured heart rate.
    ///   - athlete: Supplies the zone settings/sex/pace model `estimator` estimates against.
    /// - Returns: The estimated ``TrainingLoad`` for the instantiated workout.
    /// - Throws: Whatever `instantiate(name:values:)` throws.
    public func expectedLoad(
        values: [String: Double] = [:],
        estimator: PlannedLoadEstimator,
        athlete: AthleteProfile
    ) throws(WorkoutTemplateError) -> TrainingLoad {
        estimator.estimatedLoad(for: try instantiate(values: values), athlete: athlete)
    }
}

extension TemplateValue where Value == Double {
    fileprivate func resolve(_ resolve: (String) throws(WorkoutTemplateError) -> Double) throws(WorkoutTemplateError) -> Double {
        switch self {
        case .fixed(let value): value
        case .parameter(let key): try resolve(key)
        }
    }
}

extension TemplateValue where Value == Int {
    /// - Note: A resolved parameter value is rounded to the nearest integer rather than truncated,
    ///   so a fractional value from a non-integer-snapped input (e.g. a UI slider) doesn't silently
    ///   drop a whole repetition (`7.9` rounds to `8`, not `7`).
    fileprivate func resolve(_ resolve: (String) throws(WorkoutTemplateError) -> Double) throws(WorkoutTemplateError) -> Int {
        switch self {
        case .fixed(let value): value
        case .parameter(let key): Int(try resolve(key).rounded())
        }
    }
}

extension TemplateStepGoal {
    fileprivate func resolve(_ resolve: (String) throws(WorkoutTemplateError) -> Double) throws(WorkoutTemplateError) -> StepGoal {
        switch self {
        case .time(let value): .time(try value.resolve(resolve))
        case .distance(let value): .distance(try value.resolve(resolve))
        case .open: .open
        }
    }
}

extension WorkoutTemplate {
    private enum CodingKeys: String, CodingKey {
        case id, name, titleName, sport, venue, parameters, blocks, purpose, sessionType, recoveryDays, archivedDate
    }

    /// Decodes a template, reading the venue an older version stored inside the sport
    /// (`indoorRunning`/`outdoorRunning`) when there's no `venue` of its own, and treating a missing
    /// `purpose` as ``WorkoutPurpose/general``, a missing or unknown `sessionType` as `nil` and a missing
    /// or undecodable `recoveryDays` as `nil`.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        titleName = try container.decodeIfPresent(String.self, forKey: .titleName)
        let storedSport = try container.decode(StoredSport.self, forKey: .sport)
        sport = storedSport.sport
        venue = try container.decodeIfPresent(Venue.self, forKey: .venue) ?? storedSport.legacyVenue
        parameters = try container.decode([WorkoutTemplateParameter].self, forKey: .parameters)
        blocks = try container.decode([TemplateBlock].self, forKey: .blocks)
        purpose = try container.decodeIfPresent(WorkoutPurpose.self, forKey: .purpose) ?? .general
        sessionType = (try? container.decodeIfPresent(SessionType.self, forKey: .sessionType)) ?? nil
        recoveryDays = (try? container.decodeIfPresent(RecoveryDays.self, forKey: .recoveryDays)) ?? nil
        archivedDate = try container.decodeIfPresent(Date.self, forKey: .archivedDate)
    }
}
