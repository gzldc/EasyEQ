import CoreAudio
import Foundation
import os

let audioLog = Logger(subsystem: "app.easyeq.EasyEQ", category: "audio")

/// A Core Audio failure with the failing call and OSStatus, ready to be logged or shown.
struct CoreAudioError: Error, CustomStringConvertible {
    let call: String
    let status: OSStatus

    var description: String { "\(call) failed (\(status) \(Self.fourCC(status)))" }

    static func fourCC(_ status: OSStatus) -> String {
        let value = UInt32(bitPattern: status)
        let bytes = [24, 16, 8, 0].map { UInt8((value >> UInt32($0)) & 0xFF) }
        guard bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) else { return "'?'" }
        return "'" + String(decoding: bytes, as: UTF8.self) + "'"
    }
}

/// Throws (and logs) when `status` is not `noErr`.
func check(_ status: OSStatus, _ call: String) throws {
    guard status == noErr else {
        let error = CoreAudioError(call: call, status: status)
        audioLog.error("\(error.description, privacy: .public)")
        throw error
    }
}

func address(
    _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
    element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
}

func getProperty<T>(
    _ object: AudioObjectID, _ addr: AudioObjectPropertyAddress, initial: T
) throws -> T {
    var addr = addr
    var value = initial
    var size = UInt32(MemoryLayout<T>.size)
    let status = withUnsafeMutablePointer(to: &value) {
        AudioObjectGetPropertyData(object, &addr, 0, nil, &size, UnsafeMutableRawPointer($0))
    }
    try check(status, "AudioObjectGetPropertyData(\(object), selector \(CoreAudioError.fourCC(OSStatus(bitPattern: addr.mSelector))))")
    return value
}

func setProperty<T>(_ object: AudioObjectID, _ addr: AudioObjectPropertyAddress, _ value: T) throws {
    var addr = addr
    var value = value
    let status = withUnsafeMutablePointer(to: &value) {
        AudioObjectSetPropertyData(object, &addr, 0, nil, UInt32(MemoryLayout<T>.size), UnsafeRawPointer($0))
    }
    try check(status, "AudioObjectSetPropertyData(\(object), selector \(CoreAudioError.fourCC(OSStatus(bitPattern: addr.mSelector))))")
}

func getString(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> String {
    try getProperty(object, address(selector), initial: "" as CFString) as String
}

func defaultOutputDeviceID() throws -> AudioDeviceID {
    let id = try getProperty(
        AudioObjectID(kAudioObjectSystemObject), address(kAudioHardwarePropertyDefaultOutputDevice),
        initial: AudioDeviceID(kAudioObjectUnknown))
    guard id != AudioDeviceID(kAudioObjectUnknown) else {
        throw CoreAudioError(call: "default output device lookup (none)", status: kAudioHardwareBadDeviceError)
    }
    return id
}

/// The Core Audio process object for this process, or `nil` if it cannot be resolved.
func ownProcessObjectID() -> AudioObjectID? {
    var pid = getpid()
    var addr = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
    var object = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    let status = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &addr, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object)
    guard status == noErr, object != AudioObjectID(kAudioObjectUnknown) else {
        audioLog.error("Could not translate own pid to a process object (OSStatus \(status))")
        return nil
    }
    return object
}

/// True when some process other than this one is currently producing output audio.
func otherProcessIsOutputting(excluding own: AudioObjectID?) -> Bool {
    var addr = address(kAudioHardwarePropertyProcessObjectList)
    var size: UInt32 = 0
    let system = AudioObjectID(kAudioObjectSystemObject)
    guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return false }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return false }
    for id in ids where id != own {
        let running = try? getProperty(id, address(kAudioProcessPropertyIsRunningOutput), initial: UInt32(0))
        if let running, running != 0 { return true }
    }
    return false
}

// MARK: - Real-time render context

/// Everything the IOProc touches. All memory is allocated up front; `render` never allocates, locks or logs.
final class RenderContext: @unchecked Sendable {
    static let maxFrames = 4096
    static let maxChannels = 8

    private let processor: EQProcessor
    private let scratch: UnsafeMutablePointer<Float>
    private let list: UnsafeMutableAudioBufferListPointer
    /// [0] = IOProc callbacks so far, [1] = 1 once a non-zero input sample was seen.
    /// Written by the audio thread, read by the main thread; a stale read is harmless.
    private let counters: UnsafeMutablePointer<UInt32>

    init(processor: EQProcessor) {
        self.processor = processor
        scratch = .allocate(capacity: Self.maxChannels * Self.maxFrames)
        scratch.initialize(repeating: 0, count: Self.maxChannels * Self.maxFrames)
        list = AudioBufferList.allocate(maximumBuffers: Self.maxChannels)
        counters = .allocate(capacity: 2)
        counters.initialize(repeating: 0, count: 2)
    }

    deinit {
        scratch.deallocate()
        list.unsafeMutablePointer.deallocate()
        counters.deallocate()
    }

    var callbackCount: UInt32 { counters[0] }
    var sawSignal: Bool { counters[1] != 0 }

    /// Builds the IOProc block outside any actor context so it carries no isolation checks.
    nonisolated func makeIOBlock() -> AudioDeviceIOBlock {
        return { [self] _, input, _, output, _ in
            render(input: input, output: output)
        }
    }

    /// De-interleaves the tap input into planar scratch channels, runs the EQ in place, and writes the result
    /// (interleaved or planar) to the output buffers. Handles buffers larger than the scratch via chunking.
    private func render(input: UnsafePointer<AudioBufferList>, output: UnsafeMutablePointer<AudioBufferList>) {
        counters[0] &+= 1
        let outList = UnsafeMutableAudioBufferListPointer(output)
        let inList = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let floatSize = MemoryLayout<Float>.size

        func frames(_ list: UnsafeMutableAudioBufferListPointer) -> Int {
            guard list.count > 0, list[0].mNumberChannels > 0 else { return 0 }
            return Int(list[0].mDataByteSize) / (Int(list[0].mNumberChannels) * floatSize)
        }
        let outFrames = frames(outList)
        let total = min(frames(inList), outFrames)
        let checkSignal = counters[1] == 0

        var done = 0
        while done < total {
            let n = min(Self.maxFrames, total - done)

            // Input -> planar scratch.
            var channels = 0
            for b in 0..<inList.count {
                let buffer = inList[b]
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let nc = Int(buffer.mNumberChannels)
                for k in 0..<nc where channels + k < Self.maxChannels {
                    let dst = scratch + (channels + k) * Self.maxFrames
                    let src = data + done * nc + k
                    if checkSignal {
                        var any = false
                        for i in 0..<n {
                            let v = src[i * nc]
                            dst[i] = v
                            if v != 0 { any = true }
                        }
                        if any { counters[1] = 1 }
                    } else {
                        for i in 0..<n { dst[i] = src[i * nc] }
                    }
                }
                channels = min(channels + nc, Self.maxChannels)
            }

            // EQ in place on the planar channels.
            list.count = channels
            for c in 0..<channels {
                list[c] = AudioBuffer(
                    mNumberChannels: 1, mDataByteSize: UInt32(n * floatSize),
                    mData: UnsafeMutableRawPointer(scratch + c * Self.maxFrames))
            }
            if channels > 0 { processor.process(list, frameCount: n) }

            // Planar scratch -> output.
            var outChannel = 0
            for b in 0..<outList.count {
                let buffer = outList[b]
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let nc = Int(buffer.mNumberChannels)
                for k in 0..<nc {
                    let c = outChannel + k
                    let dst = data + done * nc + k
                    let source: Int = c < channels ? c : (channels == 1 ? 0 : -1)
                    if source >= 0 {
                        let src = scratch + source * Self.maxFrames
                        for i in 0..<n { dst[i * nc] = src[i] }
                    } else {
                        for i in 0..<n { dst[i * nc] = 0 }
                    }
                }
                outChannel += nc
            }
            done += n
        }

        // Silence anything the input did not cover.
        if total < outFrames {
            for b in 0..<outList.count {
                let buffer = outList[b]
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let nc = Int(buffer.mNumberChannels)
                (data + total * nc).update(repeating: 0, count: (outFrames - total) * nc)
            }
        }
    }
}
