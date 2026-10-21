import Testing
@testable import EasyEQCore

@Test func flatResponseIsZero() {
    let s = EQSettings.flat(.ten)
    #expect(abs(s.responseDB(at: 1000)) < 0.001)
    #expect(s.autoPreampDB() == 0)
}

@Test func singleBandPeaksAtItsGain() {
    var s = EQSettings.flat(.ten); s.gains[6] = 6   // 2 kHz
    #expect(abs(s.responseDB(at: 2000) - 6) < 0.6)
    #expect(abs(s.responseDB(at: 100)) < 0.5)
}

@Test func conversionInterpolatesInLogFrequency() {
    let voice = EQSettings(layout: .ten, gains: [-6,-5,-4,-3,-1,0,2,2.5,0,0])
    let c = voice.converted(to: .thirtyOne)
    #expect(c.gains.count == 31)
    #expect(c.gains[0] == -6)                    // 20 Hz → clamps to 32 Hz value
    #expect(abs(c.gains[3] - (-5.7)) < 0.051)    // 40 Hz between 32(-6) and 64(-5)
    let back = c.converted(to: .ten)
    for (a, b) in zip(back.gains, voice.gains) { #expect(abs(a - b) <= 0.1 + 1e-9) }
    #expect(EQSettings.flat(.ten).converted(to: .fifteen) == .flat(.fifteen))
}

@Test func allBandsMaxedGetsNegativePreamp() {
    let s = EQSettings(layout: .ten, gains: Array(repeating: 12, count: 10))
    #expect(s.autoPreampDB() <= -12)
}

@Test func highBandStableAt44k() {
    let c = BiquadCoefficients.peaking(frequency: 20_000, gainDB: 12, q: 4.3, sampleRate: 44_100)
    #expect([c.b0, c.b1, c.b2, c.a1, c.a2].allSatisfy { $0.isFinite })
}
