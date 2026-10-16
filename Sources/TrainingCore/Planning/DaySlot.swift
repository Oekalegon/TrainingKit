/// A part of the day an athlete can run in, one element of ``RunAvailability``.
///
/// Three coarse parts rather than clock times: the generator only needs to know whether a second
/// session fits on a day, not when exactly it starts. How many runs a day gets is
/// ``RunAvailability/runs(on:)``, and the generator (MVP5-119) puts each run in its own free part.
///
/// Availability stored while there were only two parts (`morning` and a combined
/// `afternoonEvening`) still decodes: ``RunAvailability`` reads the old `afternoonEvening` name,
/// both as a free slot and as a key of its slot options, as both ``afternoon`` and ``evening``. It
/// is no longer a case and is never written again.
public enum DaySlot: String, Sendable, Codable, Hashable, CaseIterable {
    /// Before midday.
    case morning
    /// From midday until the early evening.
    case afternoon
    /// The evening.
    case evening

    /// The name the combined afternoon-and-evening part was stored under before it was split.
    static let legacyAfternoonEvening = "afternoonEvening"

    /// The slots a stored name stands for: the one slot, both ``afternoon`` and ``evening`` for the
    /// legacy combined name, and none for a name this version does not know.
    static func slots(forStoredName name: String) -> [DaySlot] {
        if name == legacyAfternoonEvening { return [.afternoon, .evening] }
        return DaySlot(rawValue: name).map { [$0] } ?? []
    }
}
