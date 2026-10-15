/// A part of the day an athlete can run in, one element of ``RunAvailability``.
///
/// Two coarse slots rather than clock times: the generator only needs to know whether a second
/// session fits on a day (two-a-day needs both slots), not when exactly it starts.
public enum DaySlot: String, Sendable, Codable, Hashable, CaseIterable {
    /// Before midday.
    case morning
    /// From midday through the evening.
    case afternoonEvening
}
