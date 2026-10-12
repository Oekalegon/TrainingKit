import Foundation

/// A reusable structured workout in the athlete's library, e.g. "6x400m intervals".
public struct StructuredWorkout: Identifiable, Sendable, Codable, Hashable {
    /// A stable identifier for this workout.
    public let id: UUID
    /// The workout's display name.
    public var name: String
    /// The kind of activity this workout is for.
    public var sport: Sport
    /// Where the workout is done, if known. Mapped to WorkoutKit's indoor/outdoor location, so the
    /// Watch doesn't ask.
    public var venue: Venue?
    /// The ordered blocks making up this workout.
    public var blocks: [WorkoutBlock]
    /// Identity of a WorkoutKit plan this workout was recovered from; `nil` if none. Scheduling
    /// doesn't use it: a scheduled entry's id is its ``PlannedActivity``'s id (MVP2-55).
    public var workoutKitID: UUID?
    /// The ``WorkoutTemplate`` this workout was instantiated from, or `nil` for one built by hand or
    /// created before this field existed. Together with ``parameterValues`` it's what lets an app
    /// re-open the template's parameters and instantiate an edited copy (MVP2-41).
    public var templateID: UUID?
    /// The resolved value of every parameter the template declares, as used to build ``blocks`` —
    /// `nil` exactly when ``templateID`` is. Stored rather than re-derived from `blocks`, since
    /// several parameters can collapse into the same step values.
    public var parameterValues: [String: Double]?
    /// What the workout is for: ``WorkoutPurpose/general`` for an ordinary one, or a field test
    /// whose result is measured from the activity linked to its plan (MVP2-153). Taken from the
    /// template when instantiated. Absent from workouts saved before this field existed, which
    /// decode as ``WorkoutPurpose/general``.
    public var purpose: WorkoutPurpose

    /// Creates a structured workout.
    ///
    /// - Parameters:
    ///   - id: A stable identifier; defaults to a new random `UUID`.
    ///   - name: The workout's display name.
    ///   - sport: The kind of activity this workout is for.
    ///   - venue: Where the workout is done, if known.
    ///   - blocks: The ordered blocks making up this workout.
    ///   - workoutKitID: Identity of the synced WorkoutKit plan, if already synced.
    ///   - templateID: The template this workout was instantiated from, if any.
    ///   - parameterValues: The resolved parameter values it was instantiated with, if any.
    ///   - purpose: What the workout is for; defaults to ``WorkoutPurpose/general``.
    public init(
        id: UUID = UUID(),
        name: String,
        sport: Sport,
        venue: Venue? = nil,
        blocks: [WorkoutBlock],
        workoutKitID: UUID? = nil,
        templateID: UUID? = nil,
        parameterValues: [String: Double]? = nil,
        purpose: WorkoutPurpose = .general
    ) {
        self.id = id
        self.name = name
        self.sport = sport
        self.venue = venue
        self.blocks = blocks
        self.workoutKitID = workoutKitID
        self.templateID = templateID
        self.parameterValues = parameterValues
        self.purpose = purpose
    }
}

extension StructuredWorkout {
    private enum CodingKeys: String, CodingKey {
        case id, name, sport, venue, blocks, workoutKitID, templateID, parameterValues, purpose
    }

    /// Decodes a workout, reading the venue an older version stored inside the sport
    /// (`indoorRunning`/`outdoorRunning`) when there's no `venue` of its own, and treating a missing
    /// `purpose` as ``WorkoutPurpose/general``.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        let storedSport = try container.decode(StoredSport.self, forKey: .sport)
        sport = storedSport.sport
        venue = try container.decodeIfPresent(Venue.self, forKey: .venue) ?? storedSport.legacyVenue
        blocks = try container.decode([WorkoutBlock].self, forKey: .blocks)
        workoutKitID = try container.decodeIfPresent(UUID.self, forKey: .workoutKitID)
        templateID = try container.decodeIfPresent(UUID.self, forKey: .templateID)
        parameterValues = try container.decodeIfPresent([String: Double].self, forKey: .parameterValues)
        purpose = try container.decodeIfPresent(WorkoutPurpose.self, forKey: .purpose) ?? .general
    }
}
