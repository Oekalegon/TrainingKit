/// A named classification of an athlete's heart-rate zones 1–5, matching the standard
/// five-zone effort model used throughout endurance coaching (e.g. Friel's *Training Bible*):
/// easy aerobic effort at the low end, through to maximal, largely anaerobic effort at the top.
///
/// Deliberately separate from the bare `zone: Int` used throughout `HeartRateZoneModel`,
/// ``TimeInZone``, and ``TimeInZoneBuilder`` rather than replacing it: those stay Int-keyed
/// because a segment or histogram bin can fall in zone 0 ("below zone 1"), which isn't a real
/// zone and has no name. This type exists purely to give the five real zones a name — display
/// strings and colors are UI concerns and belong in each app, not here (see e.g.
/// `Sport`/`BiologicalSex`'s own `+Display` extensions).
public enum HeartRateZone: Int, Sendable, Codable, Hashable, CaseIterable {
    /// Very light effort, easily sustained — active recovery between hard sessions.
    case recovery = 1
    /// Comfortable, conversational effort — the bulk of aerobic base-building volume.
    case aerobic = 2
    /// Moderately hard, "comfortably hard" effort — sustainable for a long interval but not a
    /// full conversation.
    case tempo = 3
    /// Hard effort at or just below lactate threshold — sustainable for tens of minutes at most.
    case threshold = 4
    /// Maximal or near-maximal effort — short, hard intervals near VO2 max.
    case anaerobic = 5
}
