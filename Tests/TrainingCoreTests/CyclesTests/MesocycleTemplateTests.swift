import Testing
@testable import TrainingCore

@Suite("MesocycleTemplate built-in presets")
struct MesocycleTemplateTests {
    @Test("3:1 is three build micros followed by one recovery micro")
    func threeToOne() {
        #expect(MesocycleTemplate.threeToOne.microPhases == [.build, .build, .build, .recovery])
    }

    @Test("2:1 is two build micros followed by one recovery micro")
    func twoToOne() {
        #expect(MesocycleTemplate.twoToOne.microPhases == [.build, .build, .recovery])
    }

    @Test("linear has no recovery micro")
    func linear() {
        #expect(MesocycleTemplate.linear.microPhases == [.build])
    }
}
