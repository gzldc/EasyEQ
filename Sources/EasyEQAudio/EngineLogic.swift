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

    /// What the engine knows about a running (or starting) pipeline, for deciding whether a device event matters.
    struct SessionSnapshot: Equatable, Sendable {
        var outputUID: String
        var sampleRate: Double
    }

    enum RebuildDecision: Equatable, Sendable {
        /// The event does not concern the current pipeline.
        case none
        /// The output is gone (not alive / not listed / no default): destroy the pipeline now, rebuild once it is back.
        case teardownOnly
        case rebuild
    }

    /// Sample rates closer than this are the same rate.
    static let sampleRateTolerance = 0.5

    /// Decides what a device event (default output changed, device list changed, liveness or rate changed) means for
    /// the pipeline. Only a different default output UID, a different sample rate, or a device coming back warrants
    /// a rebuild; a device-list change that leaves the output alone must not touch the pipeline (a rebuild mutes
    /// system audio for a moment).
    /// - Parameters:
    ///   - current: the running pipeline, or `nil` if there is none.
    ///   - newDefaultUID: UID of the system default output right now, `nil` if it cannot be resolved.
    ///   - newRate: its nominal sample rate, `nil` if unknown (an unknown rate never triggers a rebuild).
    ///   - outputAlive: the pipeline's output device and the default output device are both alive and listed.
    static func shouldRebuild(
        current: SessionSnapshot?, newDefaultUID: String?, newRate: Double?, outputAlive: Bool
    ) -> RebuildDecision {
        guard let current else {
            return newDefaultUID != nil && outputAlive ? .rebuild : .none
        }
        guard outputAlive, let newDefaultUID else { return .teardownOnly }
        if newDefaultUID != current.outputUID { return .rebuild }
        if let newRate, abs(newRate - current.sampleRate) > sampleRateTolerance { return .rebuild }
        return .none
    }

    /// Why the pipeline looked at the devices.
    enum DeviceEvent: String, Sendable {
        case defaultOutput, deviceList, outputAlive, sampleRate, serviceRestarted
    }

    /// Events that may mean the output device is dying. Answering them needs queries to that device's driver, which
    /// can block for 30 s on a hung driver while the tap keeps system audio muted, so the pipeline is destroyed first
    /// (tap first, system audio comes back) and the facts are checked afterwards. A genuine rate change rebuilds
    /// anyway; a spurious event just costs one rebuild.
    static func teardownBeforeQuerying(_ event: DeviceEvent) -> Bool {
        event == .outputAlive || event == .sampleRate
    }

    /// How often a lost output device is looked for, and how long before the engine gives up and shows a failure.
    static let waitRecheckSeconds: TimeInterval = 2
    static let waitGiveUpSeconds: TimeInterval = 15

    enum WaitDecision: Equatable, Sendable { case rebuild, keepWaiting, giveUp }

    /// What to do on a periodic recheck while waiting for a lost output device to come back.
    static func waitDecision(elapsed: TimeInterval, defaultUsable: Bool) -> WaitDecision {
        if defaultUsable { return .rebuild }
        return elapsed >= waitGiveUpSeconds ? .giveUp : .keepWaiting
    }

    /// Whether `device` still counts as present given the (possibly failed) device-list query. An unknown list
    /// (`nil`: the query failed) never proves a device gone.
    static func isListed(_ device: UInt32, in list: [UInt32]?) -> Bool {
        list?.contains(device) ?? true
    }

    /// Whether the "Core Audio is not responding" state (watchdog timeout) is showing. Only a watchdog sets it.
    /// The next build, any sign of life from the pipeline and a stop clear it. A plain failure leaves it as it
    /// is: it can only be the late result of the very build that timed out (a repair restarting `coreaudiod` makes
    /// the stuck call return an error), and clearing it would take the Repair button away before the retry starts.
    enum UnresponsiveEvent: Sendable {
        case watchdogFired, buildStarted, pipelineResponded, otherFailure, stopped
    }

    static func coreAudioUnresponsive(after event: UnresponsiveEvent, previous: Bool = false) -> Bool {
        switch event {
        case .watchdogFired: return true
        case .otherFailure: return previous
        case .buildStarted, .pipelineResponded, .stopped: return false
        }
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
