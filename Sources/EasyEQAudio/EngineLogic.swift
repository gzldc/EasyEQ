import CoreAudio
import Foundation

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
