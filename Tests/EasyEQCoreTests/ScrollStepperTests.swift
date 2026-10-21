import Testing
@testable import EasyEQCore

@Test func wheelNotchesAreWholeSteps() {
    var s = ScrollStepper()
    #expect(s.steps(forDelta: 1, precise: false) == 1)
    #expect(s.steps(forDelta: -1, precise: false) == -1)
    #expect(s.steps(forDelta: 3, precise: false) == 3)
    #expect(s.steps(forDelta: 0.2, precise: false) == 1)     // never swallowed
    #expect(s.steps(forDelta: -0.2, precise: false) == -1)
    #expect(s.steps(forDelta: 0, precise: false) == 0)
}

@Test func trackpadDeltasAccumulate() {
    var s = ScrollStepper(pointsPerStep: 6)
    #expect(s.steps(forDelta: 2, precise: true) == 0)
    #expect(s.steps(forDelta: 2, precise: true) == 0)
    #expect(s.steps(forDelta: 2, precise: true) == 1)        // 6 points reached
    #expect(s.steps(forDelta: 14, precise: true) == 2)       // 14 / 6 = 2, remainder 2
    #expect(s.steps(forDelta: 4, precise: true) == 1)        // 2 + 4 = 6
    #expect(s.steps(forDelta: -13, precise: true) == -2)
}

@Test func resetDropsRemainder() {
    var s = ScrollStepper(pointsPerStep: 6)
    #expect(s.steps(forDelta: 5, precise: true) == 0)
    s.reset()
    #expect(s.steps(forDelta: 5, precise: true) == 0)
    #expect(s.steps(forDelta: .nan, precise: true) == 0)
}
