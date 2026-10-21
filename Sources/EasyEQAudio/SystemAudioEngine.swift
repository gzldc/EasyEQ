import AppKit
import CoreAudio
import Foundation
import os

public enum EngineState: Equatable, Sendable {
    case stopped
    case running(deviceName: String)
    case permissionDenied
    case failed(String)
}

/// Routes all system audio through `processor` using a Core Audio process tap (no driver needed):
/// a global tap (muted while tapped) feeds a private aggregate device whose output is the default output device.
@MainActor
public final class SystemAudioEngine: ObservableObject {
    @Published public private(set) var state: EngineState = .stopped
    public let processor: EQProcessor

    private static let bufferFrames: UInt32 = 256
    private static let permissionTimeout = 3   // seconds of exact zeros while others play => denied

    private struct Session {
        var tapID = AudioObjectID(kAudioObjectUnknown)
        var aggregateID = AudioObjectID(kAudioObjectUnknown)
        var procID: AudioDeviceIOProcID?
        var started = false
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var context: RenderContext?
        var rateListener: AudioObjectPropertyListenerBlock?
        var ownProcess: AudioObjectID?
    }

    private struct SendableDevice: @unchecked Sendable {
        let aggregateID: AudioObjectID
        let procID: AudioDeviceIOProcID?
    }

    private var session = Session()
    private var wantsRunning = false
    private var buildGeneration = 0
    private var systemListener: AudioObjectPropertyListenerBlock?
    private var rebuildTask: Task<Void, Never>?
    private var monitorTask: Task<Void, Never>?
    private var activeObserver: NSObjectProtocol?

    public init() {
        processor = EQProcessor(sampleRate: 48_000, channelCount: 2)
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.wantsRunning, self.state == .permissionDenied else { return }
                audioLog.info("App became active while permission was denied; retrying")
                self.build()
            }
        }
    }

    deinit {
        if let activeObserver { NotificationCenter.default.removeObserver(activeObserver) }
    }

    // MARK: - Public API

    public func start() {
        guard !wantsRunning else { return }
        audioLog.info("start requested")
        wantsRunning = true
        installSystemListener()
        build()
    }

    /// Idempotent; safe to call from `applicationWillTerminate`. Always leaves system audio un-muted.
    public func stop() {
        let wasActive = wantsRunning || session.tapID != AudioObjectID(kAudioObjectUnknown)
        wantsRunning = false
        rebuildTask?.cancel()
        rebuildTask = nil
        removeSystemListener()
        teardown()
        if wasActive { audioLog.info("stopped") }
        state = .stopped
    }

    // MARK: - Build / teardown

    private func build() {
        teardown()
        guard wantsRunning else { return }
        do {
            try buildPipeline()
        } catch let error as CoreAudioError {
            teardown()
            if error.call.hasPrefix("AudioHardwareCreateProcessTap") {
                audioLog.error("Tap creation failed; treating as permission denied")
                state = .permissionDenied
            } else {
                state = .failed(error.description)
            }
        } catch {
            teardown()
            audioLog.error("Unexpected error: \(String(describing: error), privacy: .public)")
            state = .failed(String(describing: error))
        }
    }

    private func buildPipeline() throws {
        // 1. Tap: everything except this process, muted at the hardware while tapped.
        let own = ownProcessObjectID()
        session.ownProcess = own
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: own.map { [$0] } ?? [])
        description.name = "EasyEQ"
        description.muteBehavior = .mutedWhenTapped
        description.isPrivate = true
        var tapID = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateProcessTap(description, &tapID), "AudioHardwareCreateProcessTap")
        session.tapID = tapID
        audioLog.info("Created process tap \(tapID)")

        // 2. Default output device.
        let deviceID = try defaultOutputDeviceID()
        session.deviceID = deviceID
        let deviceUID = try getString(deviceID, kAudioDevicePropertyDeviceUID)
        let deviceName = try getString(deviceID, kAudioObjectPropertyName)
        let rate = try getProperty(deviceID, address(kAudioDevicePropertyNominalSampleRate), initial: Float64(0))
        audioLog.info("Output device \(deviceName, privacy: .public) (\(deviceUID, privacy: .public)) at \(rate) Hz")
        guard rate > 0 else { throw CoreAudioError(call: "nominal sample rate (zero)", status: kAudioHardwareBadPropertySizeError) }

        let tapFormat = try getProperty(
            tapID, address(kAudioTapPropertyFormat), initial: AudioStreamBasicDescription())
        audioLog.info("""
            Tap format: \(tapFormat.mSampleRate) Hz, \(tapFormat.mChannelsPerFrame) ch, \
            flags 0x\(String(tapFormat.mFormatFlags, radix: 16)), bits \(tapFormat.mBitsPerChannel), \
            interleaved \((tapFormat.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0)
            """)
        guard tapFormat.mFormatID == kAudioFormatLinearPCM,
              tapFormat.mFormatFlags & kAudioFormatFlagIsFloat != 0, tapFormat.mBitsPerChannel == 32
        else { throw CoreAudioError(call: "tap format check (not Float32 PCM)", status: kAudioDeviceUnsupportedFormatError) }

        // 3. Private aggregate device: output device as main sub-device plus the tap.
        let aggregateUID = UUID().uuidString
        let dictionary: [String: Any] = [
            kAudioAggregateDeviceNameKey: "EasyEQ Tap",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceMainSubDeviceKey: deviceUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: deviceUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: description.uuid.uuidString,
            ]],
        ]
        var aggregateID = AudioObjectID(kAudioObjectUnknown)
        try check(
            AudioHardwareCreateAggregateDevice(dictionary as CFDictionary, &aggregateID),
            "AudioHardwareCreateAggregateDevice")
        session.aggregateID = aggregateID
        audioLog.info("Created aggregate device \(aggregateID)")

        // 4. Small buffer for low latency (best effort).
        do {
            try setProperty(aggregateID, address(kAudioDevicePropertyBufferFrameSize), Self.bufferFrames)
        } catch {
            audioLog.error("Could not set buffer size to \(Self.bufferFrames); using device default")
        }
        let actualFrames = try? getProperty(
            aggregateID, address(kAudioDevicePropertyBufferFrameSize), initial: UInt32(0))
        audioLog.info("Aggregate buffer size: \(actualFrames ?? 0) frames")
        logStreamConfiguration(aggregateID, scope: kAudioObjectPropertyScopeInput, label: "input")
        logStreamConfiguration(aggregateID, scope: kAudioObjectPropertyScopeOutput, label: "output")

        // 5. IOProc.
        processor.setSampleRate(rate)
        let context = RenderContext(processor: processor)
        session.context = context
        var procID: AudioDeviceIOProcID?
        try check(
            AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil, context.makeIOBlock()),
            "AudioDeviceCreateIOProcIDWithBlock")
        session.procID = procID
        session.started = true   // so teardown always stops the device, even while the start is still pending

        // AudioDeviceStart blocks while the system-audio permission prompt is on screen, so keep it off the
        // main thread. `generation` discards the result if the pipeline was torn down in the meantime.
        let generation = buildGeneration
        let startDevice = SendableDevice(aggregateID: aggregateID, procID: procID)
        Task.detached(priority: .userInitiated) { [weak self] in
            let status = AudioDeviceStart(startDevice.aggregateID, startDevice.procID)
            await self?.finishStart(generation: generation, status: status, deviceName: deviceName)
        }
    }

    private func finishStart(generation: Int, status: OSStatus, deviceName: String) {
        guard generation == buildGeneration, wantsRunning else { return }
        if status != noErr {
            let error = CoreAudioError(call: "AudioDeviceStart", status: status)
            audioLog.error("\(error.description, privacy: .public)")
            teardown()
            state = .failed(error.description)
            return
        }

        // Follow sample-rate changes of the output device.
        let listener = Self.makeListener { [weak self] in
            audioLog.info("Output device nominal sample rate changed")
            self?.scheduleRebuild()
        }
        var rateAddress = address(kAudioDevicePropertyNominalSampleRate)
        if AudioObjectAddPropertyListenerBlock(session.deviceID, &rateAddress, .main, listener) == noErr {
            session.rateListener = listener
        }

        state = .running(deviceName: deviceName)
        audioLog.info("Running on \(deviceName, privacy: .public)")
        startMonitoring()
    }

    /// Stop device -> destroy IOProc -> destroy aggregate -> destroy tap. Never throws; logs each failure.
    private func teardown() {
        buildGeneration += 1
        monitorTask?.cancel()
        monitorTask = nil
        var s = session
        session = Session()

        if let listener = s.rateListener {
            var rateAddress = address(kAudioDevicePropertyNominalSampleRate)
            AudioObjectRemovePropertyListenerBlock(s.deviceID, &rateAddress, .main, listener)
        }
        if s.started {
            logFailure(AudioDeviceStop(s.aggregateID, s.procID), "AudioDeviceStop")
            s.started = false
        }
        if let procID = s.procID {
            logFailure(AudioDeviceDestroyIOProcID(s.aggregateID, procID), "AudioDeviceDestroyIOProcID")
        }
        if s.aggregateID != AudioObjectID(kAudioObjectUnknown) {
            logFailure(AudioHardwareDestroyAggregateDevice(s.aggregateID), "AudioHardwareDestroyAggregateDevice")
        }
        if s.tapID != AudioObjectID(kAudioObjectUnknown) {
            logFailure(AudioHardwareDestroyProcessTap(s.tapID), "AudioHardwareDestroyProcessTap")
            audioLog.info("Destroyed process tap; system audio is un-muted")
        }
        s.context = nil
    }

    private func logFailure(_ status: OSStatus, _ call: String) {
        if status != noErr { audioLog.error("\(CoreAudioError(call: call, status: status).description, privacy: .public)") }
    }

    private func logStreamConfiguration(_ device: AudioObjectID, scope: AudioObjectPropertyScope, label: String) {
        var addr = address(kAudioDevicePropertyStreamConfiguration, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr, size > 0 else { return }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, raw) == noErr else { return }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        let channels = list.map { Int($0.mNumberChannels) }
        audioLog.info("Aggregate \(label, privacy: .public) buffers (channels each): \(channels.map(String.init).joined(separator: ","), privacy: .public)")
    }

    // MARK: - Device / rate changes

    /// Builds a listener block outside any actor context; it hops to the main actor itself.
    nonisolated private static func makeListener(_ action: @escaping @MainActor @Sendable () -> Void) -> AudioObjectPropertyListenerBlock {
        return { _, _ in
            Task { @MainActor in action() }
        }
    }

    private func installSystemListener() {
        guard systemListener == nil else { return }
        let listener = Self.makeListener { [weak self] in
            audioLog.info("Default output device changed")
            self?.scheduleRebuild()
        }
        var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
        let status = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main, listener)
        if status == noErr { systemListener = listener } else { logFailure(status, "AudioObjectAddPropertyListenerBlock(default output)") }
    }

    private func removeSystemListener() {
        guard let listener = systemListener else { return }
        var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main, listener)
        systemListener = nil
    }

    /// Coalesces bursts of change notifications, then tears down and rebuilds.
    private func scheduleRebuild() {
        guard wantsRunning else { return }
        rebuildTask?.cancel()
        rebuildTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self, self.wantsRunning else { return }
            audioLog.info("Rebuilding audio pipeline")
            self.build()
        }
    }

    // MARK: - Permission detection

    /// A denied tap delivers exact zeros. If other processes are producing audio yet we only see zeros for
    /// `permissionTimeout` seconds, assume denied: tear down (un-muting the system) and wait for the app to be
    /// re-activated. Stops checking as soon as any non-zero sample arrives.
    private func startMonitoring() {
        monitorTask?.cancel()
        guard let context = session.context else { return }
        let own = session.ownProcess
        monitorTask = Task { @MainActor [weak self] in
            var zeroSeconds = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled, let self else { return }
                if context.sawSignal {
                    audioLog.info("Tap is delivering audio (\(context.callbackCount) callbacks so far)")
                    return
                }
                if context.callbackCount > 0, otherProcessIsOutputting(excluding: own) {
                    zeroSeconds += 1
                } else {
                    zeroSeconds = 0
                }
                if zeroSeconds >= Self.permissionTimeout {
                    audioLog.error("Tap delivered only zeros for \(zeroSeconds) s while other audio was playing; assuming permission denied")
                    self.teardown()
                    self.state = .permissionDenied
                    return
                }
            }
        }
    }
}
