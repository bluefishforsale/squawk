// Captures the microphone for a dictation. Building an audio engine and
// opening the input device takes 350 to 450 ms, long enough to swallow the
// first word. Two things shorten that. The engine is built ahead of time and
// kept stopped, which holds no microphone and shows no indicator, so a key
// press only has to start it. And the recorder can keep the device open
// between dictations and hand back a little audio from just before the key
// went down. How long it stays open is the user's call, because macOS shows
// the microphone indicator the whole time. The default is the private one:
// open only while the key is held.

import AVFoundation
import FluidAudio
import os

enum MicrophoneReadiness: String, CaseIterable, Identifiable {
    /// Opened on key down and closed on release. Can clip the first syllable.
    case onDemand
    /// Stays open for a short while after each dictation.
    case warm
    /// Open the whole time Squawk is enabled. Never clips.
    case always

    var id: String { rawValue }

    var label: String {
        switch self {
        case .onDemand: "Only while held"
        case .warm: "30 s after use"
        case .always: "Always"
        }
    }
}

final class Recorder {
    /// Called on the main queue with the RMS amplitude of each captured
    /// buffer while recording, for the level meter.
    var onLevel: (Float) -> Void = { _ in }
    /// Called on the main queue when the microphone cannot be opened.
    var onError: (Error) -> Void = { _ in }

    private struct Buffers {
        var recording = false
        var captured: [Float] = []
        /// The most recent audio while idle, so a dictation can start slightly
        /// in the past. Overwritten continuously and never leaves memory.
        var preRoll: [Float] = []
        /// What the device is delivering, read from the audio itself.
        var sampleRate = 0.0
    }

    private static let preRollSeconds = 0.35
    private static let warmSeconds = 30.0

    private let queue = DispatchQueue(label: "squawk.recorder", qos: .userInteractive)
    private let buffers = OSAllocatedUnfairLock(initialState: Buffers())
    /// Built ahead of a dictation and reused. Stopped unless `isRunning`.
    private var engine: AVAudioEngine?
    private var isRunning = false
    private var isEnabled = false
    private var readiness = MicrophoneReadiness.onDemand
    private var cooldown = 0
    private var configurationObserver: NSObjectProtocol?

    func setReadiness(_ readiness: MicrophoneReadiness, enabled: Bool) {
        queue.async { [self] in
            self.readiness = readiness
            isEnabled = enabled
            let recording = buffers.withLock { $0.recording }
            if !enabled {
                if !recording { discard() }
            } else if readiness == .always {
                open()
            } else {
                if !recording, readiness == .onDemand { close() }
                build()
            }
        }
    }

    /// Returns at once; the device opens on the recorder's own queue so the
    /// caller can put the overlay on screen without waiting for it.
    func start() {
        queue.async { [self] in
            cooldown += 1
            buffers.withLock { state in
                state.recording = true
                state.captured = state.preRoll
                state.preRoll = []
            }
            open()
        }
    }

    /// Returns the recording as 16 kHz mono, the format Parakeet expects.
    func stop() throws -> [Float] {
        let (samples, rate) = queue.sync { (finish(), buffers.withLock { $0.sampleRate }) }
        guard !samples.isEmpty, rate > 0 else { return [] }
        return try AudioConverter().resample(samples, from: rate)
    }

    func cancel() {
        queue.sync { _ = finish() }
    }

    private func finish() -> [Float] {
        let samples = buffers.withLock { state in
            defer {
                state.recording = false
                state.captured = []
            }
            return state.captured
        }
        switch readiness {
        case .always:
            break
        case .onDemand:
            close()
        case .warm:
            cooldown += 1
            let ticket = cooldown
            queue.asyncAfter(deadline: .now() + Self.warmSeconds) { [self] in
                guard ticket == cooldown, readiness == .warm else { return }
                close()
            }
        }
        return samples
    }

    /// Makes a stopped engine with its tap in place, ready to start.
    private func build() {
        guard engine == nil else { return }
        let engine = AVAudioEngine()
        let buffers = buffers
        // No format is named, so the tap takes whatever the device delivers
        // and cannot disagree with it after the device changes.
        engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            guard let channel = buffer.floatChannelData?[0] else { return }
            let chunk = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
            let rate = buffer.format.sampleRate
            let recording = buffers.withLock { state -> Bool in
                state.sampleRate = rate
                if state.recording {
                    state.captured.append(contentsOf: chunk)
                } else {
                    state.preRoll.append(contentsOf: chunk)
                    let excess = state.preRoll.count - Int(rate * Self.preRollSeconds)
                    if excess > 0 { state.preRoll.removeFirst(excess) }
                }
                return state.recording
            }
            guard recording else { return }
            let rms = (chunk.reduce(0) { $0 + $1 * $1 } / Float(max(chunk.count, 1))).squareRoot()
            DispatchQueue.main.async { self?.onLevel(rms) }
        }
        engine.prepare()
        self.engine = engine
        // A new input device (AirPods connecting) invalidates the engine.
        // Replace it, so the next dictation opens the new device.
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            self?.queue.async {
                guard let self else { return }
                self.discard()
                if self.readiness == .always {
                    self.open()
                } else if self.isEnabled {
                    self.build()
                }
            }
        }
    }

    private func open() {
        guard !isRunning else { return }
        let began = ProcessInfo.processInfo.systemUptime
        do {
            build()
            do {
                try engine?.start()
            } catch {
                // An engine built before the device changed can refuse to
                // start. A new one gets a single try.
                discard()
                build()
                try engine?.start()
            }
        } catch {
            discard()
            let onError = onError
            DispatchQueue.main.async { onError(error) }
            return
        }
        isRunning = true
        let format = engine?.inputNode.outputFormat(forBus: 0)
        log.notice(
            "microphone open: \(format?.channelCount ?? 0, privacy: .public) ch at \(Int(format?.sampleRate ?? 0), privacy: .public) Hz, took \(Int((ProcessInfo.processInfo.systemUptime - began) * 1000), privacy: .public) ms")
    }

    /// Stops listening and keeps the engine for the next dictation.
    private func close() {
        engine?.stop()
        isRunning = false
        buffers.withLock { $0.preRoll = [] }
    }

    private func discard() {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
        configurationObserver = nil
        engine?.inputNode.removeTap(onBus: 0)
        close()
        engine = nil
    }
}
