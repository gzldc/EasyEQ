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
///
/// This class is the main-actor face of the engine: it owns the published state and the "should it run" intent.
/// Every Core Audio call lives in `EnginePipeline` on its own queue, so a hung `coreaudiod` can never block the UI;
/// the state stays `.starting` until the pipeline reports back.
@MainActor
public final class SystemAudioEngine: ObservableObject {
    @Published public private(set) var state: EngineState = .stopped
    /// True while the tap has delivered only zeros even though other processes report producing output.
    /// A hint only (a paused tab also holds an output stream open); the pipeline keeps running and is rebuilt
    /// when the app is next activated.
    @Published public private(set) var permissionSuspected = false
    /// True when the last failure was the build watchdog timing out, i.e. `coreaudiod` itself is not answering.
    /// Only a restart of the audio service helps then, so the UI offers a repair next to Retry. Cleared by the next
    /// build, by any sign of life from the pipeline, by any other failure, and by a stop.
    @Published public private(set) var coreAudioUnresponsive = false
    public let processor: EQProcessor

    private let pipeline: EnginePipeline
    private var wantsRunning = false
    private var rebuildTask: Task<Void, Never>?
    private var monitorTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
    private var activeObserver: NSObjectProtocol?

    public init() {
        let processor = EQProcessor(sampleRate: 48_000, channelCount: 2)
        self.processor = processor
        pipeline = EnginePipeline(processor: processor)
        pipeline.publish = { [weak self] epoch, outcome in
            Task { @MainActor in self?.apply(outcome, epoch: epoch) }
        }
        pipeline.onDeviceChange = { [weak self] change in
            Task { @MainActor in self?.apply(change) }
        }
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

    /// Returns immediately; the state is `.starting` until the background build finishes.
    public func start() {
        guard !wantsRunning else { return }
        audioLog.info("start requested")
        wantsRunning = true
        pipeline.startListening()
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

    /// Idempotent. Always leaves system audio un-muted (once the background teardown has run).
    public func stop() {
        halt()
        pipeline.stop()
    }

    /// `stop()` for `applicationWillTerminate`: waits for the teardown, but at most `timeout` seconds, so a
    /// wedged `coreaudiod` cannot keep the app from quitting. Returns `false` if the wait timed out.
    @discardableResult
    public func stopForTermination(timeout: TimeInterval = 2) -> Bool {
        halt()
        let finished = pipeline.stopAndWait(timeout: timeout)
        if !finished { audioLog.error("Teardown did not finish within \(timeout) s; quitting anyway") }
        return finished
    }

    // MARK: - Build / teardown

    /// Main-actor half of a stop: forget the intent, invalidate in-flight results, publish `.stopped`.
    private func halt() {
        let wasActive = wantsRunning
        wantsRunning = false
        rebuildTask?.cancel()
        rebuildTask = nil
        monitorTask?.cancel()
        monitorTask = nil
        watchdogTask?.cancel()
        watchdogTask = nil
        permissionSuspected = false
        setUnresponsive(.stopped)
        pipeline.gate.advance()   // results of any build issued earlier are now stale
        if wasActive { audioLog.info("stopped") }
        state = .stopped
    }

    private func build() {
        guard wantsRunning else { return }
        monitorTask?.cancel()
        monitorTask = nil
        permissionSuspected = false
        setUnresponsive(.buildStarted)
        state = .starting
        let epoch = pipeline.gate.advance()
        startWatchdog(epoch: epoch)
        pipeline.build(epoch: epoch)
    }

    /// If the build phase has not reported back in time (a wedged `coreaudiod`), say so instead of showing
    /// "starting" forever, so the user gets the failure text and Retry. Covers the build only: the pipeline
    /// reports `.awaitingStart` before `AudioDeviceStart`, which may wait on the permission prompt as long as it likes.
    private func startWatchdog(epoch: Int) {
        watchdogTask?.cancel()
        watchdogTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: EngineLogic.buildWatchdogSeconds * 1_000_000_000)
            guard !Task.isCancelled, let self else { return }
            guard EngineLogic.watchdogShouldFail(
                state: self.state, epochIsCurrent: self.pipeline.gate.isCurrent(epoch), wantsRunning: self.wantsRunning)
            else { return }
            audioLog.error("Audio build did not finish within \(EngineLogic.buildWatchdogSeconds) s; Core Audio may be unresponsive")
            self.state = .failed("Core Audio did not respond within \(EngineLogic.buildWatchdogSeconds) s")
            self.setUnresponsive(.watchdogFired)
        }
    }

    /// Receives a pipeline result. Anything from a superseded build is dropped.
    private func apply(_ outcome: PipelineOutcome, epoch: Int) {
        guard wantsRunning, pipeline.gate.isCurrent(epoch) else { return }
        switch outcome {
        case .awaitingStart:
            watchdogTask?.cancel()
            watchdogTask = nil
            // A build that finished late, after the watchdog gave up, is progressing again.
            if case .failed = state { state = .starting }
            setUnresponsive(.pipelineResponded)
        case .failed(let failure):
            watchdogTask?.cancel()
            watchdogTask = nil
            state = failure
            setUnresponsive(.otherFailure)
        case .running(let deviceName, let context, let own):
            watchdogTask?.cancel()
            watchdogTask = nil
            state = .running(deviceName: deviceName)
            setUnresponsive(.pipelineResponded)
            startMonitoring(context: context, ownProcess: own)
        }
    }

    private func setUnresponsive(_ event: EngineLogic.UnresponsiveEvent) {
        let value = EngineLogic.coreAudioUnresponsive(after: event)
        if value != coreAudioUnresponsive { coreAudioUnresponsive = value }
    }

    // MARK: - Device / rate changes

    /// A device event the pipeline decided matters (it already ignored the rest).
    private func apply(_ change: DeviceChange) {
        guard wantsRunning else { return }
        switch change {
        case .rebuild:
            scheduleRebuild()
        case .deviceLost(let epoch):
            // The pipeline is already gone (torn down on its queue). A reply that crosses a newer build is stale.
            guard pipeline.gate.isCurrent(epoch) else { return }
            audioLog.info("Output device lost; waiting for it to come back")
            rebuildTask?.cancel()
            rebuildTask = nil
            monitorTask?.cancel()
            monitorTask = nil
            permissionSuspected = false
            setUnresponsive(.buildStarted)
            state = .starting
        }
    }

    /// Coalesces bursts of change notifications, then rebuilds.
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
    private func startMonitoring(context: RenderContext, ownProcess own: AudioObjectID?) {
        monitorTask?.cancel()
        monitorTask = Task { @MainActor [weak self] in
            var hint = PermissionHint()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled, self != nil else { return }
                // The process list is a Core Audio query, so it is made off the main thread, and only when it matters.
                let others = !context.sawSignal && context.callbackCount > 0
                    ? await EnginePipeline.othersOutputting(excluding: own) : false
                guard !Task.isCancelled, let self else { return }
                let suspected = hint.observe(
                    sawSignal: context.sawSignal, callbacks: context.callbackCount, othersOutputting: others)
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
