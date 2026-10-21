import CoreAudio
import Foundation
import Testing
import EasyEQCore
@testable import EasyEQAudio

// MARK: - Helpers

private func sine(hz: Double, sr: Double, seconds: Double, amp: Double) -> [Float] {
    let n = Int(sr * seconds)
    return (0..<n).map { Float(amp * sin(2 * Double.pi * hz * Double($0) / sr)) }
}

/// Deterministic white noise in [-amp, amp] (xorshift64*, fixed seed).
private func noise(count: Int, amp: Double, seed: UInt64 = 0x1234_5678_9ABC_DEF1) -> [Float] {
    var state = seed
    return (0..<count).map { _ in
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        let r = state &* 2_685_821_657_736_338_717
        let u = Double(r >> 11) / Double(1 << 53)
        return Float((u * 2 - 1) * amp)
    }
}

private func rmsDB(_ x: ArraySlice<Float>) -> Double {
    var sum = 0.0
    for v in x { sum += Double(v) * Double(v) }
    return 10 * log10(max(sum / Double(x.count), 1e-30))
}

/// RMS of the last half of the signal in dB.
private func tailRMSDB(_ x: [Float]) -> Double {
    rmsDB(x[(x.count / 2)...])
}

/// Wraps non-interleaved channel arrays in an AudioBufferList and runs them through `process`
/// in blocks. `beforeBlock` is called with the block index before each block.
private func run(
    _ p: EQProcessor,
    input: [[Float]],
    blockSize: Int = 512,
    beforeBlock: ((Int) -> Void)? = nil
) -> [[Float]] {
    let channels = input.count
    let total = input[0].count
    let list = AudioBufferList.allocate(maximumBuffers: channels)
    defer { free(list.unsafeMutablePointer) }
    var storage: [UnsafeMutablePointer<Float>] = []
    for c in 0..<channels {
        let mem = UnsafeMutablePointer<Float>.allocate(capacity: blockSize)
        storage.append(mem)
        list[c] = AudioBuffer(
            mNumberChannels: 1,
            mDataByteSize: UInt32(blockSize * MemoryLayout<Float>.size),
            mData: UnsafeMutableRawPointer(mem)
        )
    }
    defer { storage.forEach { $0.deallocate() } }

    var output = Array(repeating: [Float](), count: channels)
    var start = 0
    var block = 0
    while start < total {
        let n = min(blockSize, total - start)
        beforeBlock?(block)
        for c in 0..<channels {
            for i in 0..<n { storage[c][i] = input[c][start + i] }
        }
        p.process(list, frameCount: n)
        for c in 0..<channels {
            output[c].append(contentsOf: UnsafeBufferPointer(start: storage[c], count: n))
        }
        start += n
        block += 1
    }
    return output
}

private func settings(_ layout: BandLayout, _ gains: [Int: Double]) -> EQSettings {
    var s = EQSettings.flat(layout)
    for (i, g) in gains { s.gains[i] = g }
    return s
}

// MARK: - Tests

@Test func flatIsTransparent() {
    let input = noise(count: 24_000, amp: 0.8)

    // Flat and enabled.
    let p = EQProcessor(sampleRate: 48_000, channelCount: 1)
    p.update(settings: .flat(.ten), enabled: true)
    let out = run(p, input: [input])[0]
    for (a, b) in zip(input, out) { #expect(abs(a - b) <= 1e-5) }

    // Non-flat settings but disabled from the start.
    let q = EQProcessor(sampleRate: 48_000, channelCount: 1)
    q.update(settings: settings(.ten, [5: 6, 2: -4]), enabled: false)
    let out2 = run(q, input: [input])[0]
    for (a, b) in zip(input, out2) { #expect(abs(a - b) <= 1e-5) }
}

@Test func disablingFadesToExactPassthrough() {
    let sr = 48_000.0
    let input = sine(hz: 1000, sr: sr, seconds: 1, amp: 0.3)
    let p = EQProcessor(sampleRate: sr, channelCount: 1)
    p.update(settings: settings(.ten, [5: 12]), enabled: true)
    let out = run(p, input: [input], beforeBlock: { block in
        if block == 10 { p.update(settings: settings(.ten, [5: 12]), enabled: false) }
    })[0]
    // After the fade completes (well under 0.5 s) the output equals the input.
    for i in (input.count / 2)..<input.count { #expect(abs(input[i] - out[i]) <= 1e-5) }
    // While enabled the boost+preamp curve is applied, so the signal was changed earlier on.
    #expect(zip(input, out).prefix(4_000).contains { abs($0 - $1) > 1e-3 })
}

@Test func gainMatchesCurveAt1k() {
    let sr = 48_000.0
    let s = settings(.ten, [5: 6])
    let p = EQProcessor(sampleRate: sr, channelCount: 1)
    p.update(settings: s, enabled: true)
    let input = sine(hz: 1000, sr: sr, seconds: 1, amp: 0.1) // -20 dBFS
    let out = run(p, input: [input])[0]
    let measured = tailRMSDB(out) - tailRMSDB(input)
    let expected = s.responseDB(at: 1000, sampleRate: sr) + s.autoPreampDB(sampleRate: sr)
    #expect(abs(measured - expected) <= 0.5)
}

@Test func allBandsMaxNeverClip() {
    let s = EQSettings(layout: .ten, gains: Array(repeating: 12, count: 10))
    let p = EQProcessor(sampleRate: 48_000, channelCount: 1)
    p.update(settings: s, enabled: true)
    let out = run(p, input: [noise(count: 48_000, amp: 0.9)])[0]
    #expect(out.allSatisfy { $0.isFinite })
    #expect((out.map { abs($0) }.max() ?? 0) <= 1.0)
}

@Test func stableAt44kWith31Bands() {
    let gains = (0..<31).map { $0 % 2 == 0 ? 12.0 : -12.0 }
    let p = EQProcessor(sampleRate: 44_100, channelCount: 2)
    p.update(settings: EQSettings(layout: .thirtyOne, gains: gains), enabled: true)
    let out = run(p, input: [noise(count: 44_100, amp: 0.5, seed: 1), noise(count: 44_100, amp: 0.5, seed: 2)])
    for ch in out {
        #expect(ch.allSatisfy { $0.isFinite })
        #expect((ch.map { abs($0) }.max() ?? 0) <= 1.0)
    }
}

@Test func fastGainChangesDoNotClick() {
    let sr = 48_000.0
    let input = sine(hz: 1000, sr: sr, seconds: 0.5, amp: 0.5)
    let p = EQProcessor(sampleRate: sr, channelCount: 1)
    let blockSize = 480 // 10 ms
    let out = run(p, input: [input], blockSize: blockSize, beforeBlock: { block in
        let gain = block % 2 == 0 ? -12.0 : 12.0
        p.update(settings: settings(.ten, [5: gain]), enabled: true)
    })[0]
    var maxStep: Float = 0
    for i in 1..<out.count { maxStep = max(maxStep, abs(out[i] - out[i - 1])) }
    #expect(maxStep < 0.1)
    #expect(out.allSatisfy { $0.isFinite })
}

@Test func sampleRateChangeKeepsResponse() {
    let s = settings(.ten, [5: 6, 7: -5])
    let p = EQProcessor(sampleRate: 48_000, channelCount: 1)
    p.update(settings: s, enabled: true)
    let in48 = sine(hz: 1000, sr: 48_000, seconds: 1, amp: 0.1)
    let gain48 = tailRMSDB(run(p, input: [in48])[0]) - tailRMSDB(in48)

    p.setSampleRate(96_000)
    let in96 = sine(hz: 1000, sr: 96_000, seconds: 1, amp: 0.1)
    let gain96 = tailRMSDB(run(p, input: [in96])[0]) - tailRMSDB(in96)

    #expect(abs(gain48 - gain96) <= 0.5)
}

@Test func layoutChangeStaysFinite() {
    let p = EQProcessor(sampleRate: 48_000, channelCount: 1)
    let input = noise(count: 48_000, amp: 0.5)
    let out = run(p, input: [input], beforeBlock: { block in
        let layouts: [BandLayout] = [.ten, .thirtyOne, .fifteen]
        let layout = layouts[(block / 20) % 3]
        p.update(settings: EQSettings(layout: layout, gains: Array(repeating: 9, count: layout.bandCount)), enabled: true)
    })[0]
    #expect(out.allSatisfy { $0.isFinite })
    #expect((out.map { abs($0) }.max() ?? 0) <= 1.0)
}

@Test func channelsAreIndependentAndExtraChannelsPassThrough() {
    let channels = 10 // the processor handles max(8, channelCount) = 8 channels
    let p = EQProcessor(sampleRate: 48_000, channelCount: 2)
    p.update(settings: settings(.ten, [5: 12]), enabled: true)
    let tone = sine(hz: 1000, sr: 48_000, seconds: 0.25, amp: 0.2)
    let silence = [Float](repeating: 0, count: tone.count)
    var input = Array(repeating: silence, count: channels)
    input[0] = tone
    input[7] = tone
    input[9] = tone
    let out = run(p, input: input)
    #expect(out[1].allSatisfy { $0 == 0 })       // silent channel stays silent (no crosstalk)
    #expect(out[9] == tone)                      // beyond the supported channel count: untouched
    #expect(out[0] != tone)                      // processed
    #expect(out[7] == out[0])                    // identical input -> identical output on any channel
}

@Test func gainRampFollowsTwentyMillisecondTimeConstant() {
    let sr = 48_000.0
    let p = EQProcessor(sampleRate: sr, channelCount: 1)
    p.update(settings: .flat(.ten), enabled: true)
    let input = sine(hz: 1000, sr: sr, seconds: 0.3, amp: 0.2)
    // Cut band 1K by 12 dB at t = 0.1 s (block 10 of 480 samples); no preamp is involved for a pure cut.
    let out = run(p, input: [input], blockSize: 480, beforeBlock: { block in
        if block == 10 { p.update(settings: settings(.ten, [5: -12]), enabled: true) }
    })[0]
    func levelChangeDB(afterMs ms: Double) -> Double {
        let start = 4_800 + Int(ms * sr / 1000)
        let window = Int(0.005 * sr)
        return rmsDB(out[start..<(start + window)]) - rmsDB(input[start..<(start + window)])
    }
    // Centre of the window at 22.5 ms: expected -12 * (1 - exp(-22.5/20)) ~= -8.1 dB.
    #expect(abs(levelChangeDB(afterMs: 20) - (-8.1)) <= 1.5)
    // Early on it must not have jumped, and eventually it settles at -12 dB.
    #expect(levelChangeDB(afterMs: 0) > -4)
    #expect(abs(levelChangeDB(afterMs: 150) - (-12)) <= 0.5)
}
