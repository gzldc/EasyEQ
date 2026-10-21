import CoreAudio
import Foundation
import os
import EasyEQCore

/// Real-time equalizer: preamp -> biquad chain (Direct Form II Transposed, Double state) -> peak limiter.
///
/// Threading model
/// - `update(settings:enabled:)` / `setSampleRate(_:)` run on any non-real-time thread. They compute everything
///   expensive (auto preamp) up front, then publish plain-old-data targets into a fixed-size "pending" slot
///   guarded by an `os_unfair_lock`.
/// - `process(_:frameCount:)` runs on the audio thread. It only ever `try`-locks that lock (`Synchronization.Atomic`
///   needs macOS 15, the deployment target is 14.4). If the control thread holds it, the audio thread keeps its
///   previous targets for this block and picks the new ones up on the next. The audio thread never blocks,
///   allocates, or touches Swift arrays: all state lives in buffers allocated once in `init`.
public final class EQProcessor: @unchecked Sendable {
    private static let maxBands = 31
    private static let minChannels = 8
    private static let blockStep = 32            // coefficients are refreshed every 32 samples while ramping
    private static let smoothingSeconds = 0.02   // one-pole time constant for band gains and preamp
    private static let limiterThreshold = 0.8912509381337456 // -1 dBFS
    private static let limiterReleaseSeconds = 0.05
    private static let snapDB = 0.001

    private let maxChannels: Int

    // MARK: Control side (guarded by `controlLock`)
    private let controlLock = NSLock()
    private var controlSettings = EQSettings.flat(.ten)
    private var controlEnabled = false
    private var controlSampleRate: Double

    // MARK: Hand-off slot (guarded by `slotLock`, written by control thread, try-locked by audio thread)
    private let slotLock: UnsafeMutablePointer<os_unfair_lock>
    private let slotGains: UnsafeMutablePointer<Double>
    private let slotFrequencies: UnsafeMutablePointer<Double>
    private var slotBandCount = 0
    private var slotQ = 1.0
    private var slotPreampDB = 0.0
    private var slotSampleRate: Double
    private var slotGeneration = 0

    // MARK: Audio-thread state (touched only inside `process`, after `init`)
    private var seenGeneration = 0
    private var sampleRate: Double
    private var smoothingAlpha = 0.0
    private var limiterRelease = 0.0
    private var bandCount = 0
    private var q = 1.0
    private let frequencies: UnsafeMutablePointer<Double>
    private let targetGains: UnsafeMutablePointer<Double>
    private let currentGains: UnsafeMutablePointer<Double>
    private let dirty: UnsafeMutablePointer<Bool>
    private let coefficients: UnsafeMutablePointer<Double>   // [band][b0 b1 b2 a1 a2]
    private let activeBands: UnsafeMutablePointer<Int>
    private var activeCount = 0
    private let state: UnsafeMutablePointer<Double>          // [channel][band][z1 z2]
    private let limiterGain: UnsafeMutablePointer<Double>    // [channel]
    private var targetPreampDB = 0.0
    private var currentPreampDB = 0.0
    private var preampLinear = 1.0

    public init(sampleRate: Double, channelCount: Int) {
        let maxBands = Self.maxBands
        maxChannels = max(Self.minChannels, channelCount)
        controlSampleRate = sampleRate
        slotSampleRate = sampleRate
        self.sampleRate = sampleRate

        slotLock = .allocate(capacity: 1)
        slotLock.initialize(to: os_unfair_lock())
        slotGains = Self.zeroed(maxBands)
        slotFrequencies = Self.zeroed(maxBands)
        frequencies = Self.zeroed(maxBands)
        targetGains = Self.zeroed(maxBands)
        currentGains = Self.zeroed(maxBands)
        coefficients = Self.zeroed(maxBands * 5)
        state = Self.zeroed(maxChannels * maxBands * 2)
        limiterGain = Self.zeroed(maxChannels)
        for c in 0..<maxChannels { limiterGain[c] = 1 }
        dirty = .allocate(capacity: maxBands)
        dirty.initialize(repeating: false, count: maxBands)
        activeBands = .allocate(capacity: maxBands)
        activeBands.initialize(repeating: 0, count: maxBands)
        updateRateConstants()
    }

    deinit {
        slotLock.deallocate()
        for p in [slotGains, slotFrequencies, frequencies, targetGains, currentGains, coefficients, state, limiterGain] {
            p.deallocate()
        }
        dirty.deallocate()
        activeBands.deallocate()
    }

    private static func zeroed(_ count: Int) -> UnsafeMutablePointer<Double> {
        let p = UnsafeMutablePointer<Double>.allocate(capacity: count)
        p.initialize(repeating: 0, count: count)
        return p
    }

    // MARK: - Control API

    public func setSampleRate(_ sr: Double) {
        controlLock.lock()
        defer { controlLock.unlock() }
        controlSampleRate = sr
        publish()
    }

    public func update(settings: EQSettings, enabled: Bool) {
        controlLock.lock()
        defer { controlLock.unlock() }
        controlSettings = settings
        controlEnabled = enabled
        publish()
    }

    /// Must be called with `controlLock` held. Does the expensive work, then briefly takes `slotLock`.
    private func publish() {
        let layout = controlSettings.layout
        let count = min(layout.bandCount, Self.maxBands)
        let freqs = layout.frequencies
        let preamp = controlEnabled ? controlSettings.autoPreampDB(sampleRate: controlSampleRate) : 0

        os_unfair_lock_lock(slotLock)
        slotBandCount = count
        slotQ = layout.q
        for i in 0..<count {
            slotFrequencies[i] = freqs[i]
            let g = (controlEnabled && i < controlSettings.gains.count) ? controlSettings.gains[i] : 0
            slotGains[i] = g.isFinite ? g : 0
        }
        slotPreampDB = preamp.isFinite ? preamp : 0
        slotSampleRate = controlSampleRate
        slotGeneration &+= 1
        os_unfair_lock_unlock(slotLock)
    }

    // MARK: - Audio thread

    private func updateRateConstants() {
        smoothingAlpha = 1 - exp(-Double(Self.blockStep) / (Self.smoothingSeconds * sampleRate))
        limiterRelease = exp(-1 / (Self.limiterReleaseSeconds * sampleRate))
    }

    /// Picks up new targets if the control thread is not mid-publish; otherwise keeps the old ones.
    private func pullPending() {
        guard os_unfair_lock_trylock(slotLock) else { return }
        defer { os_unfair_lock_unlock(slotLock) }
        guard slotGeneration != seenGeneration else { return }
        seenGeneration = slotGeneration

        let firstUpdate = bandCount == 0
        if slotSampleRate != sampleRate {
            sampleRate = slotSampleRate
            updateRateConstants()
            markAllDirty()
        }
        if slotBandCount != bandCount {
            // Layout change: reset filter states and jump to the new gains (a brief glitch is acceptable).
            bandCount = slotBandCount
            state.update(repeating: 0, count: maxChannels * Self.maxBands * 2)
            for i in 0..<bandCount {
                frequencies[i] = slotFrequencies[i]
                targetGains[i] = slotGains[i]
                currentGains[i] = slotGains[i]
            }
            for i in bandCount..<Self.maxBands { targetGains[i] = 0; currentGains[i] = 0 }
            markAllDirty()
        } else {
            for i in 0..<bandCount { targetGains[i] = slotGains[i] }
        }
        if slotQ != q { q = slotQ; markAllDirty() }
        targetPreampDB = slotPreampDB
        if firstUpdate {
            currentPreampDB = targetPreampDB
            preampLinear = pow(10, currentPreampDB / 20)
        }
    }

    private func markAllDirty() {
        for i in 0..<Self.maxBands { dirty[i] = true }
    }

    /// True when the preamp and every band are at exactly 0 dB with no ramp pending, so the input can pass
    /// through untouched. The limiter does not keep the processor out of bypass: "off" must equal the raw sound.
    private func isSettled() -> Bool {
        if targetPreampDB != 0 || currentPreampDB != 0 { return false }
        for i in 0..<bandCount where targetGains[i] != 0 || currentGains[i] != 0 || dirty[i] { return false }
        return true
    }

    /// Entering bypass: drop any limiter reduction left over from an earlier boost.
    private func resetLimiters() {
        for c in 0..<maxChannels { limiterGain[c] = 1 }
    }

    /// Advances the one-pole ramps by one step and refreshes coefficients of the bands that moved.
    /// Returns the preamp gain (linear) at the end of the step.
    private func advanceSmoothing() -> Double {
        let alpha = smoothingAlpha
        for b in 0..<bandCount {
            let target = targetGains[b], current = currentGains[b]
            if current != target {
                var next = current + (target - current) * alpha
                if abs(target - next) < Self.snapDB { next = target }
                currentGains[b] = next
                dirty[b] = true
            }
        }
        var anyDirty = false
        for b in 0..<bandCount where dirty[b] {
            dirty[b] = false
            anyDirty = true
            let c = coefficients + b * 5
            let gain = currentGains[b]
            if gain == 0 {
                c[0] = 1; c[1] = 0; c[2] = 0; c[3] = 0; c[4] = 0
                for ch in 0..<maxChannels {   // an inactive band's state must not linger
                    let s = state + (ch * Self.maxBands + b) * 2
                    s[0] = 0; s[1] = 0
                }
            } else {
                let k = BiquadCoefficients.peaking(frequency: frequencies[b], gainDB: gain, q: q, sampleRate: sampleRate)
                c[0] = k.b0; c[1] = k.b1; c[2] = k.b2; c[3] = k.a1; c[4] = k.a2
            }
        }
        if anyDirty {
            activeCount = 0
            for b in 0..<bandCount where currentGains[b] != 0 {
                activeBands[activeCount] = b
                activeCount += 1
            }
        }
        if currentPreampDB != targetPreampDB {
            var next = currentPreampDB + (targetPreampDB - currentPreampDB) * alpha
            if abs(targetPreampDB - next) < Self.snapDB { next = targetPreampDB }
            currentPreampDB = next
            return pow(10, next / 20)
        }
        return preampLinear
    }

    public func process(_ buffers: UnsafeMutableAudioBufferListPointer, frameCount: Int) {
        pullPending()
        if bandCount == 0 { return }
        if isSettled() {
            resetLimiters()
            return
        }

        let channelTotal = min(buffers.count, maxChannels)
        var start = 0
        while start < frameCount {
            let n = min(Self.blockStep, frameCount - start)
            let preStart = preampLinear
            let preEnd = advanceSmoothing()
            preampLinear = preEnd
            if isSettled() {   // the ramp just reached 0 dB: bypass limiter and clamp from here on
                resetLimiters()
                start += n
                continue
            }
            let preStep = (preEnd - preStart) / Double(n)

            for c in 0..<channelTotal {
                let buffer = buffers[c]
                guard buffer.mNumberChannels == 1, let data = buffer.mData else { continue }
                let available = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                if start >= available { continue }
                let count = min(n, available - start)
                processChannel(
                    c, data.assumingMemoryBound(to: Float.self) + start,
                    count: count, preamp: preStart, preampStep: preStep
                )
            }
            start += n
        }
    }

    private func processChannel(
        _ channel: Int, _ samples: UnsafeMutablePointer<Float>,
        count: Int, preamp preStart: Double, preampStep: Double
    ) {
        let channelState = state + channel * Self.maxBands * 2
        let threshold = Self.limiterThreshold
        let release = limiterRelease
        var pre = preStart
        var lg = limiterGain[channel]

        for i in 0..<count {
            var v = Double(samples[i])
            if !v.isFinite { v = 0 }
            v *= pre
            pre += preampStep

            for k in 0..<activeCount {
                let b = activeBands[k]
                let c = coefficients + b * 5
                let z = channelState + b * 2
                let y = c[0] * v + z[0]
                z[0] = c[1] * v - c[3] * y + z[1]
                z[1] = c[2] * v - c[4] * y
                v = y
            }
            if !v.isFinite {   // defensive: never let a blown-up filter poison the stream
                channelState.update(repeating: 0, count: Self.maxBands * 2)
                v = 0
            }

            // Peak limiter: instant attack, exponential release.
            let magnitude = abs(v)
            var needed = 1.0
            if magnitude > threshold { needed = threshold / magnitude }
            if needed < lg {
                lg = needed
            } else {
                lg = needed + release * (lg - needed)
                if needed == 1, lg > 0.999_99 { lg = 1 }
            }
            let out = v * lg
            samples[i] = Float(min(1, max(-1, out)))
        }
        limiterGain[channel] = lg
    }
}
