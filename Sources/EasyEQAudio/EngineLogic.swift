import CoreAudio
import Foundation
import os

/// Pure decision logic for `SystemAudioEngine`, kept free of Core Audio calls so it can be unit-tested.
enum EngineLogic {
    /// Picks which of the aggregate device's input buffers belong to the tap.
    ///
    /// The aggregate's input list is the sub-device's own input streams (a headset or interface microphone,
    /// if it has any) followed by the tap's streams. Counting from the END of the list until the channel total
    /// equals the tap's channel count identifies the tap buffers. Returns the number of trailing buffers that
    /// are the tap's, or `nil` when no exact match exists (the layout is not understood and must be rejected
    /// rather than guessed at).
    static func tapBufferCount(bufferChannels: [Int], tapChannels: Int) -> Int? {
        guard tapChannels > 0 else { return nil }
        var total = 0
        var count = 0
        for channels in bufferChannels.reversed() {
            guard channels > 0 else { return nil }
            total += channels
            count += 1
            if total == tapChannels { return count }
            if total > tapChannels { return nil }
        }
        return nil
    }

    /// Per-input-stream on/off flags for the aggregate's IOProc: only the trailing `tapBufferCount` streams (the
    /// tap's) are enabled, so the sub-device's own inputs (headset microphone) are never opened. Returns `nil`
    /// when the counts cannot describe a layout.
    static func inputStreamUsage(streamCount: Int, tapBufferCount: Int) -> [Bool]? {
        guard tapBufferCount > 0, streamCount >= tapBufferCount else { return nil }
        return (0..<streamCount).map { $0 >= streamCount - tapBufferCount }
    }

    /// Whether a `kAudioDevicePropertyIOProcStreamUsage` payload of `byteSize` bytes can hold the header up to the
    /// flags array (`flagsOffset`) plus `streamCount` flags. Checked before any byte of the buffer is written.
    static func streamUsageFits(byteSize: Int, streamCount: Int, flagsOffset: Int) -> Bool {
        guard byteSize >= flagsOffset, streamCount >= 0 else { return false }
        return flagsOffset + streamCount * MemoryLayout<UInt32>.size <= byteSize
    }

    /// How long the build phase (everything before `AudioDeviceStart`) may take before the engine reports failure.
    static let buildWatchdogSeconds: UInt64 = 10

    /// A build checks this between steps: it stops when a newer request exists or the app is quitting.
    static func shouldContinueBuild(epochIsCurrent: Bool, terminating: Bool) -> Bool {
        epochIsCurrent && !terminating
    }

    /// The watchdog fires only for the build it was started for, and only while that build is still pending.
    static func watchdogShouldFail(state: EngineState, epochIsCurrent: Bool, wantsRunning: Bool) -> Bool {
        wantsRunning && epochIsCurrent && state == .starting
    }

    /// Calls that the system gates behind the audio-capture permission. Their failure means "permission".
    static func state(forFailedCall call: String, description: String) -> EngineState {
        let gated = ["AudioHardwareCreateProcessTap", "AudioDeviceStart"]
        if gated.contains(where: { call.hasPrefix($0) }) { return .permissionDenied }
        return .failed(description)
    }
}

/// Watches the tap for the signature of a denied permission: exact zeros while other processes claim to be
/// producing output. A process can hold an output stream open while playing silence (paused tab, call app), so
/// this is only ever a hint; the engine surfaces it but never tears the pipeline down because of it.
struct PermissionHint {
    static let suspicionSeconds = 3

    private(set) var zeroSeconds = 0
    private(set) var suspected = false

    /// Feed one observation per second. Returns the (possibly updated) `suspected` flag.
    @discardableResult
    mutating func observe(sawSignal: Bool, callbacks: UInt32, othersOutputting: Bool) -> Bool {
        if sawSignal {
            zeroSeconds = 0
            suspected = false
        } else if callbacks > 0 && othersOutputting {
            zeroSeconds += 1
            if zeroSeconds >= Self.suspicionSeconds { suspected = true }
        } else {
            zeroSeconds = 0   // nothing is playing, or the device is not running yet: no evidence either way
        }
        return suspected
    }
}

/// A thread-safe, strictly increasing request counter. The main actor advances it for every start / rebuild / stop;
/// work queued on the audio queue carries the value it was issued with and drops itself when a newer request exists.
final class EpochGate: @unchecked Sendable {
    private let state = OSAllocatedUnfairLock(initialState: 0)

    /// Starts a new epoch and returns it.
    @discardableResult
    func advance() -> Int { state.withLock { value in value += 1; return value } }

    var current: Int { state.withLock { $0 } }

    func isCurrent(_ epoch: Int) -> Bool { current == epoch }
}

/// Runs a closure on a queue and waits for it, but never longer than `timeout`. Used at quit so a wedged
/// Core Audio call cannot keep the app from exiting.
enum BoundedWait {
    /// Returns `true` if `work` finished within `timeout` seconds. On `false` the work keeps running on `queue`.
    static func run(on queue: DispatchQueue, timeout: TimeInterval, _ work: @escaping @Sendable () -> Void) -> Bool {
        let finished = DispatchSemaphore(value: 0)
        queue.async {
            work()
            finished.signal()
        }
        return finished.wait(timeout: .now() + timeout) == .success
    }
}
