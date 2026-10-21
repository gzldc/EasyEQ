import AppKit
import CoreAudio
import Foundation
import os

public enum EngineState: Equatable, Sendable {
    case stopped
    /// Building the pipeline, or waiting for the system-audio permission prompt to be answered.
    /// System audio is muted while the tap exists, so UI should make this visible.
    case starting
    case running(deviceName: String)
    case permissionDenied
    case failed(String)
}

/// Routes all system audio through `processor` using a Core Audio process tap (no driver needed):
/// a global tap (muted while tapped) feeds a private aggregate device whose output is the default output device.
@MainActor
public final class SystemAudioEngine: ObservableObject {
    @Published public private(set) var state: EngineState = .stopped
    /// True while the tap has delivered only zeros even though other processes report producing output.
    /// A hint only (a paused tab also holds an output stream open); the pipeline keeps running and is rebuilt
    /// when the app is next activated.
    @Published public private(set) var permissionSuspected = false
    public let processor: EQProcessor

    private static let bufferFrames: UInt32 = 256
    /// Core Audio teardown that may block (device stop while the permission prompt is open) runs here.
    private static let teardownQueue = DispatchQueue(label: "app.easyeq.EasyEQ.teardown", qos: .userInitiated)

    private struct Session {
        var tapID = AudioObjectID(kAudioObjectUnknown)
        var aggregateID = AudioObjectID(kAudioObjectUnknown)
        var procID: AudioDeviceIOProcID?
        var started = false
        /// `AudioDeviceStart` has been issued but has not returned yet (it blocks while the prompt is open).
        var startPending = false
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var context: RenderContext?
        var rateListener: AudioObjectPropertyListenerBlock?
        var ownProcess: AudioObjectID?
    }

    private struct SendableDevice: @unchecked Sendable {
        let aggregateID: AudioObjectID
        let procID: AudioDeviceIOProcID?
    }

    /// Everything `destroy` needs, detached from the main-actor session so it can run on any thread.
    private struct Teardown: @unchecked Sendable {
        var tapID: AudioObjectID
        var aggregateID: AudioObjectID
        var procID: AudioDeviceIOProcID?
        var started: Bool
        var startPending: Bool
        var context: RenderContext?   // kept alive until the IOProc is gone
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
                guard let self, self.wantsRunning, self.needsRebuildOnActivation else { return }
                audioLog.info("App became active while permission was denied, suspect or the engine had failed; rebuilding")
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

    /// Rebuilds the pipeline after a failure (or any time the user asks). No-op unless the engine is meant to run.
    public func retry() {
        guard wantsRunning else { return }
        audioLog.info("retry requested")
        rebuildTask?.cancel()
        rebuildTask = nil
        build()
    }

    private var needsRebuildOnActivation: Bool {
        if case .failed = state { return true }
        return state == .permissionDenied || permissionSuspected
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
        state = .starting
        do {
            try buildPipeline()
        } catch let error as CoreAudioError {
            teardown()
            state = EngineLogic.state(forFailedCall: error.call, description: error.description)
            if state == .permissionDenied {
                audioLog.error("\(error.call, privacy: .public) failed; treating as permission denied")
            } else {
                audioLog.error("Engine failed: \(error.description, privacy: .public)")
            }
        } catch {
            teardown()
            audioLog.error("Unexpected error: \(String(describing: error), privacy: .public)")
            state = .failed(String(describing: error))
        }
    }

    private func buildPipeline() throws {
        // 1. Tap: everything except this process, muted at the hardware while tapped.
        // Never build a tap that does not exclude this process: it would record EasyEQ's own processed output and
        // feed it back through the EQ. Fail instead; the retry path recovers once the process object resolves.
        guard let own = ownProcessObjectID() else {
            audioLog.error("Refusing to build a tap that cannot exclude this process")
            throw CoreAudioError(call: "own process object lookup", status: kAudioHardwareBadObjectError)
        }
        session.ownProcess = own
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [own])
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
        let inputChannels = streamChannels(aggregateID, scope: kAudioObjectPropertyScopeInput)
        let outputChannels = streamChannels(aggregateID, scope: kAudioObjectPropertyScopeOutput)
        audioLog.info("Aggregate input buffers (channels each): \(inputChannels.map(String.init).joined(separator: ","), privacy: .public)")
        audioLog.info("Aggregate output buffers (channels each): \(outputChannels.map(String.init).joined(separator: ","), privacy: .public)")
        // The output device's own input streams (headset mic, interface inputs) precede the tap's in the input
        // list; only the tap's trailing buffers may be processed. Refuse layouts we cannot identify.
        guard let tapBufferCount = EngineLogic.tapBufferCount(
            bufferChannels: inputChannels, tapChannels: Int(tapFormat.mChannelsPerFrame))
        else {
            audioLog.error("Unexpected aggregate input layout \(inputChannels, privacy: .public) for a \(tapFormat.mChannelsPerFrame)-channel tap")
            throw CoreAudioError(call: "aggregate input layout check", status: kAudioDeviceUnsupportedFormatError)
        }
        audioLog.info("Tap uses the last \(tapBufferCount) input buffer(s)")

        // 5. IOProc.
        processor.setSampleRate(rate)
        let context = RenderContext(processor: processor, tapBufferCount: tapBufferCount)
        session.context = context
        var procID: AudioDeviceIOProcID?
        try check(
            AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil, context.makeIOBlock()),
            "AudioDeviceCreateIOProcIDWithBlock")
        session.procID = procID

        // Enable only the tap's input streams. Left alone, starting the IOProc would also open the output device's
        // own inputs (a headset microphone: orange indicator, Bluetooth hands-free mode, unentitled mic access).
        if let procID {
            do {
                let flags = try setIOProcStreamUsage(aggregateID, procID: procID, scope: kAudioObjectPropertyScopeInput) {
                    EngineLogic.inputStreamUsage(streamCount: $0, tapBufferCount: tapBufferCount)
                }
                audioLog.info("IOProc input stream usage set (on = tap only): \(flags.map { $0 ? "on" : "off" }.joined(separator: ","), privacy: .public)")
            } catch {
                audioLog.error("Could not restrict IOProc input streams to the tap; continuing: \(String(describing: error), privacy: .public)")
            }
        }
        session.started = true   // so teardown always stops the device, even while the start is still pending
        session.startPending = true

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
        session.startPending = false
        if status != noErr {
            let error = CoreAudioError(call: "AudioDeviceStart", status: status)
            audioLog.error("\(error.description, privacy: .public)")
            teardown()
            state = EngineLogic.state(forFailedCall: error.call, description: error.description)
            if case .failed = state { audioLog.error("Engine failed: \(error.description, privacy: .public)") }
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

    /// Detaches the current session and destroys it. Normally runs synchronously (stop device -> destroy IOProc ->
    /// destroy aggregate -> destroy tap) so `applicationWillTerminate` leaves nothing behind. While the permission
    /// prompt is still pending, stopping the device can block for as long as the prompt is open, so that case
    /// runs on a background queue instead, destroying the tap first so system audio un-mutes immediately.
    private func teardown() {
        buildGeneration += 1
        monitorTask?.cancel()
        monitorTask = nil
        permissionSuspected = false
        let s = session
        session = Session()

        if let listener = s.rateListener {
            var rateAddress = address(kAudioDevicePropertyNominalSampleRate)
            AudioObjectRemovePropertyListenerBlock(s.deviceID, &rateAddress, .main, listener)
        }
        let work = Teardown(
            tapID: s.tapID, aggregateID: s.aggregateID, procID: s.procID,
            started: s.started, startPending: s.startPending, context: s.context)
        if work.startPending {
            audioLog.info("Teardown while the start is still pending; destroying off the main thread")
            Self.teardownQueue.async { Self.destroy(work) }
        } else {
            Self.destroy(work)
        }
    }

    nonisolated private static func destroy(_ t: Teardown) {
        func log(_ status: OSStatus, _ call: String) {
            if status != noErr { audioLog.error("\(CoreAudioError(call: call, status: status).description, privacy: .public)") }
        }
        func destroyTap() {
            guard t.tapID != AudioObjectID(kAudioObjectUnknown) else { return }
            log(AudioHardwareDestroyProcessTap(t.tapID), "AudioHardwareDestroyProcessTap")
            audioLog.info("Destroyed process tap; system audio is un-muted")
        }
        if t.startPending { destroyTap() }
        if t.started { log(AudioDeviceStop(t.aggregateID, t.procID), "AudioDeviceStop") }
        if let procID = t.procID { log(AudioDeviceDestroyIOProcID(t.aggregateID, procID), "AudioDeviceDestroyIOProcID") }
        if t.aggregateID != AudioObjectID(kAudioObjectUnknown) {
            log(AudioHardwareDestroyAggregateDevice(t.aggregateID), "AudioHardwareDestroyAggregateDevice")
        }
        if !t.startPending { destroyTap() }
        withExtendedLifetime(t.context) {}
    }

    private func logFailure(_ status: OSStatus, _ call: String) {
        if status != noErr { audioLog.error("\(CoreAudioError(call: call, status: status).description, privacy: .public)") }
    }

    /// Channel count of each buffer in the device's stream configuration for `scope`.
    private func streamChannels(_ device: AudioObjectID, scope: AudioObjectPropertyScope) -> [Int] {
        var addr = address(kAudioDevicePropertyStreamConfiguration, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, raw) == noErr else { return [] }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.map { Int($0.mNumberChannels) }
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

    // MARK: - Permission hint

    /// A denied tap delivers exact zeros, but so does a working tap while a process plays silence. So this only
    /// publishes `permissionSuspected` after sustained zeros with other output running, and clears it as soon as
    /// any non-zero sample arrives. It never tears the pipeline down.
    private func startMonitoring() {
        monitorTask?.cancel()
        guard let context = session.context else { return }
        let own = session.ownProcess
        monitorTask = Task { @MainActor [weak self] in
            var hint = PermissionHint()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled, let self else { return }
                let suspected = hint.observe(
                    sawSignal: context.sawSignal, callbacks: context.callbackCount,
                    othersOutputting: otherProcessIsOutputting(excluding: own))
                if suspected != self.permissionSuspected {
                    self.permissionSuspected = suspected
                    if suspected {
                        audioLog.error("Tap delivered only zeros for \(hint.zeroSeconds) s while other audio output is running; permission may be missing")
                    }
                }
                if context.sawSignal {
                    audioLog.info("Tap is delivering audio (\(context.callbackCount) callbacks so far)")
                    return
                }
            }
        }
    }
}
