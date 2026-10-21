import Foundation
import Testing
@testable import EasyEQAudio

@Suite("Pipeline threading helpers")
struct EnginePipelineLogicTests {
    @Test func streamUsagePayloadMustReachTheFlags() {
        // Header (pointer + count) is 16 bytes in the real layout; 4 flags follow.
        #expect(EngineLogic.streamUsageFits(byteSize: 16 + 4 * 4, streamCount: 4, flagsOffset: 16))
        #expect(EngineLogic.streamUsageFits(byteSize: 16, streamCount: 0, flagsOffset: 16))
        #expect(!EngineLogic.streamUsageFits(byteSize: 16 + 3 * 4, streamCount: 4, flagsOffset: 16))   // flags truncated
        #expect(!EngineLogic.streamUsageFits(byteSize: 8, streamCount: 0, flagsOffset: 16))           // header truncated
        #expect(!EngineLogic.streamUsageFits(byteSize: 64, streamCount: -1, flagsOffset: 16))
    }

    @Test func epochGateOnlyTheNewestIsCurrent() {
        let gate = EpochGate()
        #expect(gate.current == 0)
        let first = gate.advance()
        #expect(gate.isCurrent(first))
        let second = gate.advance()
        #expect(second == first + 1)
        #expect(!gate.isCurrent(first))
        #expect(gate.isCurrent(second))
    }

    @Test func epochGateIsAtomicAcrossThreads() {
        let gate = EpochGate()
        DispatchQueue.concurrentPerform(iterations: 200) { _ in gate.advance() }
        #expect(gate.current == 200)
    }

    @Test func boundedWaitReturnsTrueWhenWorkFinishes() {
        let queue = DispatchQueue(label: "test.free")
        let ran = OSAtomicFlag()
        #expect(BoundedWait.run(on: queue, timeout: 2) { ran.set() })
        #expect(ran.isSet)
    }

    @Test func boundedWaitGivesUpOnAWedgedQueue() {
        let queue = DispatchQueue(label: "test.wedged")
        let release = DispatchSemaphore(value: 0)
        queue.async { release.wait() }   // simulates a Core Audio call that never returns
        let ran = OSAtomicFlag()
        let started = Date()
        let finished = BoundedWait.run(on: queue, timeout: 0.2) { ran.set() }
        #expect(!finished)
        #expect(Date().timeIntervalSince(started) < 1.5)
        #expect(!ran.isSet)
        release.signal()
        queue.sync {}   // drains: the queued work does run once the queue frees up
        #expect(ran.isSet)
    }
}

private final class OSAtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.lock(); value = true; lock.unlock() }
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
}
