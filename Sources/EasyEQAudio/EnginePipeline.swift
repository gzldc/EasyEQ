import CoreAudio
import Foundation
import os

/// What a finished build tells the engine. Delivered tagged with the epoch the build was issued for.
enum PipelineOutcome: Sendable {
    case running(deviceName: String, context: RenderContext, ownProcess: AudioObjectID?)
    case failed(EngineState)
    /// The build phase is over and `AudioDeviceStart` is about to run (it may now wait on the permission prompt).
    case awaitingStart
}

/// What the pipeline asks the engine to do about a device event it has already classified (see `EngineLogic.shouldRebuild`).
enum DeviceChange: Sendable {
    /// The default output or its sample rate changed, or the output is back: rebuild (the engine debounces).
    case rebuild
    /// The output device died or vanished and the pipeline was torn down on the queue; wait for it to return.
    /// Carries the epoch current when it happened so a reply that arrives after a newer build is ignored.
    case deviceLost(epoch: Int)
}

/// Why the pipeline looked at the devices.
private enum DeviceEvent: String {
    case defaultOutput, deviceList, outputAlive, sampleRate
}

/// Owns every Core Audio object of the tap pipeline and performs every Core Audio call for it.
///
/// Threading contract:
/// - `queue` is a serial queue. All pipeline state (`session`, listeners) is confined to it; nothing here is ever
///   touched from the main thread, so a wedged `coreaudiod` can stall this queue but never the UI.
/// - The public methods are safe to call from any thread and return immediately (except `stopAndWait`, which is
///   bounded). Results flow back through `publish`, tagged with the epoch they were issued for; the receiver drops
///   anything that is no longer current.
/// - Queued work checks `gate` first, so a burst of requests collapses into the newest one instead of building
///   (and tearing down) a pipeline for each.
/// - `AudioDeviceStart` blocks while the system-audio permission prompt is open, so it runs on `startQueue`, not on
///   `queue`; a stop that arrives meanwhile still gets through and destroys the tap (un-muting system audio).
final class EnginePipeline: @unchecked Sendable {
    typealias Publish = @Sendable (_ epoch: Int, _ outcome: PipelineOutcome) -> Void

    let gate = EpochGate()

    private static let bufferFrames: UInt32 = 256
    /// Teardown that may block (device stop while the permission prompt is open) runs here.
    private static let teardownQueue = DispatchQueue(label: "app.easyeq.EasyEQ.teardown", qos: .userInitiated)
    private static let probeQueue = DispatchQueue(label: "app.easyeq.EasyEQ.probe", qos: .utility)

    private let queue = DispatchQueue(label: "app.easyeq.EasyEQ.pipeline", qos: .userInitiated)
    private let startQueue = DispatchQueue(label: "app.easyeq.EasyEQ.start", qos: .userInitiated, attributes: .concurrent)
    private let processor: EQProcessor

    /// Set once, before the first request, by the owner; read on `queue` afterwards.
    var publish: Publish?
    /// Called (on `queue`) when a device event needs the engine's attention. Events that do not concern the
    /// current pipeline never reach it.
    var onDeviceChange: (@Sendable (DeviceChange) -> Void)?

    // MARK: Queue-confined state

    private struct Session {
        var epoch = 0
        var tapID = AudioObjectID(kAudioObjectUnknown)
        var aggregateID = AudioObjectID(kAudioObjectUnknown)
        var procID: AudioDeviceIOProcID?
        /// Set (on `startQueue`) the moment `AudioDeviceStart` is actually called; teardown only stops a device
        /// whose start was attempted.
        var startAttempted: StartAttempt?
        /// `AudioDeviceStart` has been dispatched but has not returned yet (it blocks while the prompt is open).
        var startPending = false
        /// Left when the start task finishes; teardown of a pending start waits on it before stopping the device.
        var startDone: DispatchGroup?
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var context: RenderContext?
        var rateListener: AudioObjectPropertyListenerBlock?
        var aliveListener: AudioObjectPropertyListenerBlock?
        var ownProcess: AudioObjectID?
        /// What this pipeline was built against; empty until the output device is resolved.
        var outputUID = ""
        var sampleRate = 0.0
    }

    /// Everything `destroy` needs, detached from the session so it can run on any thread.
    private struct Teardown: @unchecked Sendable {
        var tapID: AudioObjectID
        var aggregateID: AudioObjectID
        var procID: AudioDeviceIOProcID?
        var startAttempted: StartAttempt?
        var startPending: Bool
        var startDone: DispatchGroup?
        var context: RenderContext?   // kept alive until the IOProc is gone
    }

    /// Thread-safe "AudioDeviceStart was called" flag shared between `startQueue` and teardown.
    private final class StartAttempt: @unchecked Sendable {
        private let flag = OSAllocatedUnfairLock(initialState: false)
        func markAttempted() { flag.withLock { $0 = true } }
        var attempted: Bool { flag.withLock { $0 } }
    }

    private struct StartRequest: @unchecked Sendable {
        let epoch: Int
        let attempt: StartAttempt
        let aggregateID: AudioObjectID
        let procID: AudioDeviceIOProcID?
        let tapBufferCount: Int
        let deviceName: String
        let done: DispatchGroup
    }

    private struct BuildCancelled: Error {}

    /// Set once the app is quitting: a build that notices it destroys its tap at once and stops.
    private static let terminating = OSAllocatedUnfairLock(initialState: false)

    private var session = Session()
    private var systemListener: AudioObjectPropertyListenerBlock?
    private var devicesListener: AudioObjectPropertyListenerBlock?
    /// Set between listening starting and stopping; late callbacks after a stop are ignored.
    private var listening = false
    /// The pipeline was torn down because its output went away; a returning default output rebuilds it (also when
    /// the event is only a device-list change). Cleared when a build begins and on stop.
    private var waitingForDevice = false

    init(processor: EQProcessor) {
        self.processor = processor
    }

    // MARK: - Requests (any thread, non-blocking)

    /// Starts watching the default output device and the device list. Idempotent.
    func startListening() {
        queue.async {
            self.listening = true
            self.installSystemListeners()
        }
    }

    /// Tears down whatever exists and builds a fresh pipeline for `epoch` (from `gate.advance()`).
    func build(epoch: Int) {
        queue.async { self.rebuild(epoch: epoch) }
    }

    /// Stops listening and destroys the pipeline. Call `gate.advance()` first so queued builds drop themselves.
    func stop() {
        queue.async { self.stopNow() }
    }

    /// `stop()`, but waits up to `timeout` seconds for the teardown. For `applicationWillTerminate`: the tap is
    /// destroyed first, which un-mutes system audio. Returns `false` if Core Audio did not answer in time.
    func stopAndWait(timeout: TimeInterval) -> Bool {
        Self.terminating.withLock { $0 = true }
        return BoundedWait.run(on: queue, timeout: timeout) { self.stopNow() }
    }

    /// Whether some other process is producing output. Runs on a utility queue, never on the caller's thread.
    static func othersOutputting(excluding own: AudioObjectID?) async -> Bool {
        await withCheckedContinuation { continuation in
            probeQueue.async { continuation.resume(returning: otherProcessIsOutputting(excluding: own)) }
        }
    }

    // MARK: - Queue-confined work

    private func stopNow() {
        // The tap goes first: it is what mutes system audio, so no Core Audio call that can stall precedes it.
        teardown()
        listening = false
        waitingForDevice = false
        removeSystemListeners()
    }

    private func rebuild(epoch: Int) {
        guard gate.isCurrent(epoch) else { return }   // superseded before it started
        waitingForDevice = false
        teardown()
        guard gate.isCurrent(epoch) else { return }
        do {
            try buildPipeline(epoch: epoch)
        } catch is BuildCancelled {
            // Superseded or quitting mid-build: destroy what exists now (un-muting audio); the newer request,
            // if any, builds from scratch.
            audioLog.info("Build superseded; tearing down")
            teardown()
        } catch let error as CoreAudioError {
            teardown()
            let state = EngineLogic.state(forFailedCall: error.call, description: error.description)
            if state == .permissionDenied {
                audioLog.error("\(error.call, privacy: .public) failed; treating as permission denied")
            } else {
                audioLog.error("Engine failed: \(error.description, privacy: .public)")
            }
            publish?(epoch, .failed(state))
        } catch {
            teardown()
            audioLog.error("Unexpected error: \(String(describing: error), privacy: .public)")
            publish?(epoch, .failed(.failed(String(describing: error))))
        }
    }

    private func buildPipeline(epoch: Int) throws {
        session.epoch = epoch

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
        try continueOrCancel(epoch)   // a stale tap keeps system audio muted, so stop before building on it

        // 2. Default output device.
        let deviceID = try defaultOutputDeviceID()
        session.deviceID = deviceID
        let deviceUID = try getString(deviceID, kAudioDevicePropertyDeviceUID)
        let deviceName = try getString(deviceID, kAudioObjectPropertyName)
        let rate = try getProperty(deviceID, address(kAudioDevicePropertyNominalSampleRate), initial: Float64(0))
        audioLog.info("Output device \(deviceName, privacy: .public) (\(deviceUID, privacy: .public)) at \(rate) Hz")
        guard rate > 0 else { throw CoreAudioError(call: "nominal sample rate (zero)", status: kAudioHardwareBadPropertySizeError) }
        session.outputUID = deviceUID
        session.sampleRate = rate
        installAliveListener()

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
        try continueOrCancel(epoch)

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

        // 6. Stream usage + start, off this queue: AudioDeviceStart blocks while the system-audio permission
        // prompt is on screen, and a stop must still be able to run meanwhile.
        try continueOrCancel(epoch)
        let done = DispatchGroup()
        done.enter()
        session.startDone = done
        let attempt = StartAttempt()
        session.startAttempted = attempt
        session.startPending = true
        let request = StartRequest(
            epoch: epoch, attempt: attempt, aggregateID: aggregateID, procID: procID,
            tapBufferCount: tapBufferCount, deviceName: deviceName, done: done)
        startQueue.async { self.runStart(request) }
    }

    private func continueOrCancel(_ epoch: Int) throws {
        guard EngineLogic.shouldContinueBuild(
            epochIsCurrent: gate.isCurrent(epoch), terminating: Self.terminating.withLock { $0 })
        else { throw BuildCancelled() }
    }

    /// Runs on `startQueue`. Never touches `session`; reports back to `queue`.
    private func runStart(_ request: StartRequest) {
        guard gate.isCurrent(request.epoch) else {
            audioLog.info("Start superseded before it began; skipping")
            request.done.leave()   // the superseding request tears this session down
            return
        }
        // Enable only the tap's input streams. Left alone, starting the IOProc would also open the output device's
        // own inputs (a headset microphone: orange indicator, Bluetooth hands-free mode, unentitled mic access).
        if let procID = request.procID {
            do {
                let flags = try setIOProcStreamUsage(
                    request.aggregateID, procID: procID, scope: kAudioObjectPropertyScopeInput
                ) { EngineLogic.inputStreamUsage(streamCount: $0, tapBufferCount: request.tapBufferCount) }
                audioLog.info("IOProc input stream usage set (on = tap only): \(flags.map { $0 ? "on" : "off" }.joined(separator: ","), privacy: .public)")
            } catch {
                audioLog.error("Could not restrict IOProc input streams to the tap; continuing: \(String(describing: error), privacy: .public)")
            }
        }
        // Build phase over (stream usage included): the engine's watchdog stops here; the start may now
        // legitimately wait on the permission prompt.
        publish?(request.epoch, .awaitingStart)
        request.attempt.markAttempted()
        let status = AudioDeviceStart(request.aggregateID, request.procID)
        request.done.leave()
        queue.async { self.finishStart(request, status: status) }
    }

    /// On `queue`.
    private func finishStart(_ request: StartRequest, status: OSStatus) {
        // A teardown (or a newer build) in the meantime owns the cleanup; this result is stale.
        guard session.epoch == request.epoch, session.startPending else { return }
        session.startPending = false
        if status != noErr {
            let error = CoreAudioError(call: "AudioDeviceStart", status: status)
            audioLog.error("\(error.description, privacy: .public)")
            teardown()
            let state = EngineLogic.state(forFailedCall: error.call, description: error.description)
            if case .failed = state { audioLog.error("Engine failed: \(error.description, privacy: .public)") }
            publish?(request.epoch, .failed(state))
            return
        }

        // Follow sample-rate changes of the output device. The listener runs on `queue`.
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            audioLog.info("Output device nominal sample rate changed")
            self?.handleDeviceEvent(.sampleRate)
        }
        var rateAddress = address(kAudioDevicePropertyNominalSampleRate)
        if AudioObjectAddPropertyListenerBlock(session.deviceID, &rateAddress, queue, listener) == noErr {
            session.rateListener = listener
        }
        guard let context = session.context else { return }
        audioLog.info("Running on \(request.deviceName, privacy: .public)")
        publish?(request.epoch, .running(deviceName: request.deviceName, context: context, ownProcess: session.ownProcess))
    }

    /// Detaches the current session and destroys it: tap first (system audio un-mutes immediately), then stop
    /// device -> destroy IOProc -> destroy aggregate. While the permission prompt is still pending, stopping the
    /// device can block for as long as the prompt is open, so that part is deferred to `teardownQueue`, after the
    /// start call has returned.
    private func teardown() {
        let s = session
        session = Session()

        // Tap first (inside destroy); listeners are removed afterwards so nothing that can stall precedes it.
        Self.destroy(Teardown(
            tapID: s.tapID, aggregateID: s.aggregateID, procID: s.procID,
            startAttempted: s.startAttempted, startPending: s.startPending, startDone: s.startDone, context: s.context))
        if let listener = s.rateListener {
            var rateAddress = address(kAudioDevicePropertyNominalSampleRate)
            AudioObjectRemovePropertyListenerBlock(s.deviceID, &rateAddress, queue, listener)
        }
        if let listener = s.aliveListener {
            var aliveAddress = address(kAudioDevicePropertyDeviceIsAlive)
            AudioObjectRemovePropertyListenerBlock(s.deviceID, &aliveAddress, queue, listener)
        }
    }

    private static func destroy(_ t: Teardown) {
        func log(_ status: OSStatus, _ call: String) {
            if status != noErr { audioLog.error("\(CoreAudioError(call: call, status: status).description, privacy: .public)") }
        }
        func destroyTap() {
            guard t.tapID != AudioObjectID(kAudioObjectUnknown) else { return }
            log(AudioHardwareDestroyProcessTap(t.tapID), "AudioHardwareDestroyProcessTap")
            audioLog.info("Destroyed process tap; system audio is un-muted")
        }
        func destroyDevice() {
            if t.startAttempted?.attempted == true { log(AudioDeviceStop(t.aggregateID, t.procID), "AudioDeviceStop") }
            if let procID = t.procID { log(AudioDeviceDestroyIOProcID(t.aggregateID, procID), "AudioDeviceDestroyIOProcID") }
            if t.aggregateID != AudioObjectID(kAudioObjectUnknown) {
                log(AudioHardwareDestroyAggregateDevice(t.aggregateID), "AudioHardwareDestroyAggregateDevice")
            }
            withExtendedLifetime(t.context) {}
        }
        // The tap goes first in every case: it is what mutes system audio, so nothing that can stall may precede it.
        destroyTap()
        if t.startPending {
            audioLog.info("Teardown while the start is still pending; finishing off the pipeline queue")
            teardownQueue.async {
                t.startDone?.wait()
                destroyDevice()
            }
        } else {
            destroyDevice()
        }
    }

    // MARK: - Helpers

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

    /// Output device liveness, for the session's device. Removed in `teardown`.
    private func installAliveListener() {
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            audioLog.info("Output device liveness changed")
            self?.handleDeviceEvent(.outputAlive)
        }
        var aliveAddress = address(kAudioDevicePropertyDeviceIsAlive)
        let status = AudioObjectAddPropertyListenerBlock(session.deviceID, &aliveAddress, queue, listener)
        if status == noErr {
            session.aliveListener = listener
            audioLog.info("Watching output device liveness (device \(self.session.deviceID))")
        } else {
            audioLog.error("\(CoreAudioError(call: "AudioObjectAddPropertyListenerBlock(device is alive)", status: status).description, privacy: .public)")
        }
    }

    private func installSystemListeners() {
        let system = AudioObjectID(kAudioObjectSystemObject)
        if systemListener == nil {
            let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                audioLog.info("Default output device changed")
                self?.handleDeviceEvent(.defaultOutput)
            }
            var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
            let status = AudioObjectAddPropertyListenerBlock(system, &addr, queue, listener)
            if status == noErr {
                systemListener = listener
            } else {
                audioLog.error("\(CoreAudioError(call: "AudioObjectAddPropertyListenerBlock(default output)", status: status).description, privacy: .public)")
            }
        }
        if devicesListener == nil {
            let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                audioLog.info("Device list changed")
                self?.handleDeviceEvent(.deviceList)
            }
            var addr = address(kAudioHardwarePropertyDevices)
            let status = AudioObjectAddPropertyListenerBlock(system, &addr, queue, listener)
            if status == noErr {
                devicesListener = listener
                audioLog.info("Watching default output device and device list")
            } else {
                audioLog.error("\(CoreAudioError(call: "AudioObjectAddPropertyListenerBlock(devices)", status: status).description, privacy: .public)")
            }
        }
    }

    private func removeSystemListeners() {
        let system = AudioObjectID(kAudioObjectSystemObject)
        if let listener = systemListener {
            var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
            AudioObjectRemovePropertyListenerBlock(system, &addr, queue, listener)
            systemListener = nil
        }
        if let listener = devicesListener {
            var addr = address(kAudioHardwarePropertyDevices)
            AudioObjectRemovePropertyListenerBlock(system, &addr, queue, listener)
            devicesListener = nil
        }
    }

    // MARK: - Device events (on `queue`)

    /// The default output as it is right now, or `nil` when there is none or it is not usable (not alive, not listed,
    /// or its identity cannot be read).
    private func usableDefaultOutput() -> (id: AudioDeviceID, uid: String, rate: Double?)? {
        guard let id = currentDefaultOutputDeviceID(), deviceIsAlive(id), listedDeviceIDs().contains(id),
              let uid = try? getString(id, kAudioDevicePropertyDeviceUID) else { return nil }
        let rate = try? getProperty(id, address(kAudioDevicePropertyNominalSampleRate), initial: Float64(0))
        return (id, uid, rate)
    }

    /// Classifies an event with `EngineLogic.shouldRebuild` and acts: nothing, an immediate teardown (tap first,
    /// system audio is back at once) or a request to the engine to rebuild.
    private func handleDeviceEvent(_ event: DeviceEvent) {
        guard listening else { return }
        let hasSession = !session.outputUID.isEmpty
        // A failed or denied engine still retries when the default output changes (a different device may work),
        // but unrelated list / liveness noise must not keep poking it. A pipeline lost to a dead output waits for it.
        if !hasSession && !waitingForDevice && event != .defaultOutput {
            audioLog.info("Device event (\(event.rawValue, privacy: .public)): no pipeline and not waiting for a device; ignoring")
            return
        }
        let snapshot = hasSession ? EngineLogic.SessionSnapshot(outputUID: session.outputUID, sampleRate: session.sampleRate) : nil
        let target = usableDefaultOutput()
        let sessionAlive = !hasSession || (deviceIsAlive(session.deviceID) && listedDeviceIDs().contains(session.deviceID))
        let decision = EngineLogic.shouldRebuild(
            current: snapshot, newDefaultUID: target?.uid, newRate: target?.rate, outputAlive: sessionAlive && target != nil)
        audioLog.info("""
            Device event (\(event.rawValue, privacy: .public)): pipeline \(snapshot?.outputUID ?? "none", privacy: .public) \
            @ \(snapshot?.sampleRate ?? 0) Hz, session output alive \(sessionAlive), \
            default \(target?.uid ?? "unusable", privacy: .public) @ \(target?.rate ?? 0) Hz -> \(String(describing: decision), privacy: .public)
            """)
        switch decision {
        case .none:
            break
        case .rebuild:
            onDeviceChange?(.rebuild)
        case .teardownOnly:
            audioLog.error("Output device is gone or not alive; tearing the pipeline down now and waiting for it")
            teardown()   // tap first: system audio is un-muted before anything else happens
            waitingForDevice = true
            // The default may already be usable again (the device came back under a new object): rebuild right away.
            let comeback = EngineLogic.shouldRebuild(
                current: nil, newDefaultUID: target?.uid, newRate: target?.rate, outputAlive: target != nil)
            if comeback == .rebuild {
                audioLog.info("Default output is usable again; rebuilding")
                onDeviceChange?(.rebuild)
            } else {
                onDeviceChange?(.deviceLost(epoch: gate.current))
            }
        }
    }
}
