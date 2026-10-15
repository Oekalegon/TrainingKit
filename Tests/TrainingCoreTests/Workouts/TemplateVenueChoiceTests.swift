import Foundation
import Testing
@testable import TrainingCore

@Suite("WorkoutTemplate venue choice")
struct TemplateVenueChoiceTests {
    private func template(_ sport: Sport, venue: Venue? = nil) -> WorkoutTemplate {
        WorkoutTemplate(name: "T", sport: sport, venue: venue, parameters: [], blocks: [])
    }

    @Test("a template with no venue lets the plan choose any, defaulting to outdoor")
    func openTemplate() throws {
        let t = template(.running)
        #expect(!t.isVenueFixed)
        #expect(t.venueChoices.contains(.indoor(.treadmill)))
        #expect(t.defaultVenue() == .outdoor(.road))
        #expect(t.defaultVenue(preferred: .indoor(.treadmill)) == .indoor(.treadmill))
        #expect(try t.instantiate(venue: .outdoor(.trail)).venue == .outdoor(.trail))
        #expect(try t.instantiate().venue == nil)
        #expect(try t.instantiate(venue: .indoor(.treadmill)).venue == .indoor(.treadmill))
    }

    @Test("an outdoor template without a surface offers only outdoor surfaces")
    func outdoorTemplate() throws {
        let t = template(.running, venue: .outdoor(nil))
        #expect(!t.isVenueFixed)
        #expect(t.venueChoices.allSatisfy { !$0.isIndoor })
        #expect(try t.instantiate(venue: .indoor(.treadmill)).venue == .outdoor(nil))
    }

    @Test("a venue without a surface is kept by a template that leaves its venue open")
    func surfaceLessVenueIsKept() throws {
        #expect(try template(.running).instantiate(venue: .indoor(nil)).venue == .indoor(nil))
        #expect(try template(.running, venue: .outdoor(nil)).instantiate(venue: .outdoor(nil)).venue == .outdoor(nil))
        #expect(try template(.running, venue: .outdoor(nil)).instantiate(venue: .indoor(nil)).venue == .outdoor(nil))
    }

    @Test("a template naming a surface fixes the venue")
    func fixedTemplate() throws {
        let t = template(.running, venue: .outdoor(.track))
        #expect(t.isVenueFixed)
        #expect(t.defaultVenue(preferred: .indoor(.treadmill)) == .outdoor(.track))
        #expect(try t.instantiate(venue: .outdoor(.road)).venue == .outdoor(.track))
    }

    @Test("a sport without venue variants has nothing to choose")
    func noVariants() {
        let t = template(.strength)
        #expect(t.isVenueFixed)
        #expect(t.venueChoices.isEmpty)
    }

    @Test("built-in templates: hill sprints are outdoor, the track intervals are on an outdoor track")
    func builtIns() {
        #expect(BuiltInWorkoutTemplates.baseHillSprints.venue == .outdoor(nil))
        #expect(!BuiltInWorkoutTemplates.baseHillSprints.isVenueFixed)
        #expect(BuiltInWorkoutTemplates.shortIntervalRunTrack.venue == .outdoor(.track))
        #expect(BuiltInWorkoutTemplates.shortIntervalRunTrack.isVenueFixed)
    }
}
