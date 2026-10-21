import Testing
@testable import EasyEQCore

@Test func layoutsHaveSpecFrequencies() {
    #expect(BandLayout.ten.frequencies == [32,64,125,250,500,1000,2000,4000,8000,16000])
    #expect(BandLayout.fifteen.frequencies.count == 15)
    #expect(BandLayout.thirtyOne.frequencies.count == 31)
    #expect(BandLayout.thirtyOne.frequencies.first == 20)
    #expect(BandLayout.thirtyOne.frequencies.last == 20000)
    for l in BandLayout.allCases { #expect(l.frequencies.count == l.bandCount) }
    #expect(BandLayout.ten.q == 1.41 && BandLayout.fifteen.q == 2.1 && BandLayout.thirtyOne.q == 4.3)
}

@Test func tenBandZonesMatchSpecLabels() {
    let keys = BandLayout.ten.frequencies.map(BandLayout.zoneKey(forFrequency:))
    #expect(keys == ["zone.subbass","zone.bass","zone.warmth","zone.mud","zone.body",
                     "zone.voice","zone.presence","zone.clarity","zone.sibilance","zone.air"])
}
