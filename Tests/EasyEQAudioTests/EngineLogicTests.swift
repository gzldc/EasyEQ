import Testing
@testable import EasyEQAudio

@Suite("EngineLogic")
struct EngineLogicTests {
    @Test func tapOnlyInterleaved() {
        #expect(EngineLogic.tapBufferCount(bufferChannels: [2], tapChannels: 2) == 1)
    }

    @Test func tapOnlyPlanar() {
        #expect(EngineLogic.tapBufferCount(bufferChannels: [1, 1], tapChannels: 2) == 2)
    }

    @Test func subDeviceMicComesFirst() {
        // Headset mic (1 ch) before the tap's interleaved stereo stream: only the last buffer is the tap.
        #expect(EngineLogic.tapBufferCount(bufferChannels: [1, 2], tapChannels: 2) == 1)
        // Interface with 4 inputs, planar tap.
        #expect(EngineLogic.tapBufferCount(bufferChannels: [4, 1, 1], tapChannels: 2) == 2)
    }

    @Test func rejectsLayoutsThatDoNotMatch() {
        #expect(EngineLogic.tapBufferCount(bufferChannels: [], tapChannels: 2) == nil)
        #expect(EngineLogic.tapBufferCount(bufferChannels: [1], tapChannels: 2) == nil)      // too few
        #expect(EngineLogic.tapBufferCount(bufferChannels: [4], tapChannels: 2) == nil)      // straddles
        #expect(EngineLogic.tapBufferCount(bufferChannels: [1, 2], tapChannels: 0) == nil)
        #expect(EngineLogic.tapBufferCount(bufferChannels: [0, 2], tapChannels: 2) == 1)     // zero-width ahead of the tap is ignored
    }

    @Test func streamUsageEnablesOnlyTheTrailingTapStreams() {
        // Headset mic ahead of an interleaved tap stream.
        #expect(EngineLogic.inputStreamUsage(streamCount: 2, tapBufferCount: 1) == [false, true])
        // Interface inputs ahead of a planar (2-buffer) tap.
        #expect(EngineLogic.inputStreamUsage(streamCount: 3, tapBufferCount: 2) == [false, true, true])
        // Tap only: nothing to disable.
        #expect(EngineLogic.inputStreamUsage(streamCount: 1, tapBufferCount: 1) == [true])
    }

    @Test func streamUsageRejectsImpossibleCounts() {
        #expect(EngineLogic.inputStreamUsage(streamCount: 1, tapBufferCount: 2) == nil)
        #expect(EngineLogic.inputStreamUsage(streamCount: 0, tapBufferCount: 0) == nil)
        #expect(EngineLogic.inputStreamUsage(streamCount: 2, tapBufferCount: 0) == nil)
    }

    @Test func permissionGatedCallsMapToDenied() {
        #expect(EngineLogic.state(forFailedCall: "AudioHardwareCreateProcessTap", description: "x") == .permissionDenied)
        #expect(EngineLogic.state(forFailedCall: "AudioDeviceStart", description: "x") == .permissionDenied)
        #expect(EngineLogic.state(forFailedCall: "AudioHardwareCreateAggregateDevice", description: "boom") == .failed("boom"))
    }

    @Test func hintNeedsSustainedZerosWhileOthersPlay() {
        var hint = PermissionHint()
        let first = hint.observe(sawSignal: false, callbacks: 10, othersOutputting: true)
        let second = hint.observe(sawSignal: false, callbacks: 20, othersOutputting: true)
        let third = hint.observe(sawSignal: false, callbacks: 30, othersOutputting: true)
        #expect(!first)
        #expect(!second)
        #expect(third)
    }

    @Test func hintResetsWhenEvidenceBreaks() {
        var hint = PermissionHint()
        hint.observe(sawSignal: false, callbacks: 10, othersOutputting: true)
        hint.observe(sawSignal: false, callbacks: 20, othersOutputting: true)
        hint.observe(sawSignal: false, callbacks: 30, othersOutputting: false)   // nobody playing: reset
        let after = hint.observe(sawSignal: false, callbacks: 40, othersOutputting: true)
        #expect(!after)
        #expect(hint.zeroSeconds == 1)
    }

    @Test func hintNeverFiresBeforeCallbacksOrAfterSignal() {
        var hint = PermissionHint()
        for _ in 0..<10 { hint.observe(sawSignal: false, callbacks: 0, othersOutputting: true) }
        #expect(!hint.suspected)
        for _ in 0..<5 { hint.observe(sawSignal: false, callbacks: 5, othersOutputting: true) }
        #expect(hint.suspected)
        let cleared = hint.observe(sawSignal: true, callbacks: 50, othersOutputting: true)   // audio arrived
        #expect(!cleared)
    }
}
