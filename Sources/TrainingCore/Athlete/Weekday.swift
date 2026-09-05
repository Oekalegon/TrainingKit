/// A day of the week, numbered to match `Calendar`'s `component(.weekday, from:)` (1 = Sunday).
public enum Weekday: Int, Sendable, Codable, Hashable, CaseIterable {
    case sunday = 1
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday
}
