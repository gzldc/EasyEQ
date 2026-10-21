import Testing
@testable import EasyEQCore

private func painter31() -> BandPainter {
    BandPainter(bandCount: 31, width: 310, height: 240)
}

@Test func bandAndGainMapping() {
    let p = painter31()
    #expect(p.band(atX: 5) == 0)
    #expect(p.band(atX: 305) == 30)
    #expect(p.band(atX: 999) == 30)
    #expect(p.band(atX: -50) == 0)
    #expect(p.gain(atY: 0) == 12)
    #expect(p.gain(atY: 240) == -12)
    #expect(p.gain(atY: 120) == 0)
    #expect(p.gain(atY: -30) == 12)
    #expect(p.gain(atY: 999) == -12)
}

@Test func fastStrokeCoversEveryBand() {
    let p = painter31()
    let s = p.stroke(from: (x: 5, y: 0), to: (x: 305, y: 240))
    #expect(s.map(\.index) == Array(0...30))
    #expect(s.first?.gain == 12)
    #expect(s.last?.gain == -12)
    #expect(s[15].gain == 0)                       // centre of the sweep
    #expect(zip(s, s.dropFirst()).allSatisfy { $0.gain >= $1.gain })   // monotonic descent
}

@Test func strokeRightToLeft() {
    let p = painter31()
    let s = p.stroke(from: (x: 305, y: 240), to: (x: 5, y: 0))
    #expect(s.map(\.index) == Array((0...30).reversed()))
    #expect(s.first?.gain == -12)
    #expect(s.last?.gain == 12)
    #expect(s[15].gain == 0)
}

@Test func verticalStrokeIsSingleBand() {
    let p = painter31()
    let s = p.stroke(from: (x: 155, y: 0), to: (x: 155, y: 240))
    #expect(s.count == 1)
    #expect(s[0].index == 15)
    #expect(s[0].gain == -12)
    // Same column, different x: still one band, using the end y.
    let t = p.stroke(from: (x: 151, y: 0), to: (x: 159, y: 60))
    #expect(t.count == 1)
    #expect(t[0].gain == 6)
}

@Test func strokeGainsAreRoundedAndClamped() {
    let p = BandPainter(bandCount: 10, width: 100, height: 100)
    let s = p.stroke(from: (x: -20, y: -50), to: (x: 500, y: 150))
    #expect(s.count == 10)
    #expect(s.allSatisfy { abs($0.gain) <= 12 })
    #expect(s.allSatisfy { ($0.gain * 10).rounded() == $0.gain * 10 })
    #expect(p.gain(atY: 33.3) == (((1 - 2 * 33.3 / 100) * 12 * 10).rounded() / 10))
    #expect(p.gain(atY: 50).sign == .plus)         // never -0.0
}

@Test func smoothingSoftensSpike() {
    var s = EQSettings.flat(.ten)
    s.gains[4] = 12
    let m = s.smoothed()
    #expect(m.layout == .ten)
    #expect(m.gains[4] == 6)
    #expect(m.gains[3] == 3)
    #expect(m.gains[5] == 3)
    #expect(m.gains.enumerated().filter { ![3, 4, 5].contains($0.offset) }.allSatisfy { $0.element == 0 })
}

@Test func smoothingEndsUseSingleNeighbour() {
    var s = EQSettings.flat(.ten)
    s.gains[0] = 12
    let m = s.smoothed()
    #expect(m.gains[0] == 9)
    #expect(m.gains[1] == 3)
    var e = EQSettings.flat(.ten)
    e.gains[9] = -12
    let n = e.smoothed()
    #expect(n.gains[9] == -9)
    #expect(n.gains[8] == -3)
}

@Test func smoothedFlatStaysFlat() {
    for layout in BandLayout.allCases {
        #expect(EQSettings.flat(layout).smoothed() == EQSettings.flat(layout))
    }
    let c = EQSettings(layout: .ten, gains: Array(repeating: 5, count: 10))
    #expect(c.smoothed() == c)
}

@Test func zeroed() {
    let s = EQSettings(layout: .fifteen, gains: (0..<15).map { Double($0) - 7 })
    #expect(s.zeroed() == EQSettings.flat(.fifteen))
}

@Test func nonFiniteInputsAreSafe() {
    let p = painter31()
    #expect(p.band(atX: .nan) == 0)
    #expect(p.band(atX: .infinity) == 30)
    #expect(p.band(atX: -.infinity) == 0)
    #expect(p.gain(atY: .nan) == 0)
    #expect(p.gain(atY: -.infinity) == 12)
    let s = p.stroke(from: (x: .nan, y: .nan), to: (x: 100, y: 120))
    #expect(!s.isEmpty && s.allSatisfy { (0...30).contains($0.index) && $0.gain.isFinite })
}

@Test func zeroBandsYieldNothing() {
    let p = BandPainter(bandCount: 0, width: 100, height: 100)
    #expect(p.band(atX: 50) == 0)
    #expect(p.stroke(from: (x: 0, y: 0), to: (x: 100, y: 100)).isEmpty)
    #expect(p.stroke(from: (x: 10, y: 0), to: (x: 12, y: 100)).isEmpty)
}
