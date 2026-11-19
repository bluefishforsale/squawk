// Captures the microphone for a dictation. Opening an input device takes
// 130 to 400 ms, long enough to swallow the first word or two, so the recorder
// can keep the device open between dictations and hand back a little audio
// from just before the key went down. How long it stays open is the user's
// call, because macOS shows the microphone indicator the whole time. The
// default is the private one: open only while the key is held.

import AVFoundation
import FluidAudio
import os

enum MicrophoneReadiness: String, CaseIterable, Identifiable {
    /// Opened on key down and closed on release. Clips the start of speech.
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
        var preRollLimit = 0
    }

    private static let preRollSeconds = 0.35
    private static let warmSeconds = 30.0

    private let queue = DispatchQueue(label: "squawk.recorder", qos: .userInteractive)
    private let buffers = OSAllocatedUnfairLock(initialState: Buffers())
    private var engine: AVAudioEngine?
    private var sampleRate = 0.0
    private var readiness = MicrophoneReadiness.onDemand
    private var cooldown = 0
    private var configurationObserver: NSObjectProtocol?

    func setReadiness(_ readiness: MicrophoneReadiness, enabled: Bool) {
        queue.async { [self] in
            self.readiness = readiness
            let recording = buffers.withLock { $0.recording }
            if readiness == .always, enabled {
                openIfNeeded()
            } else if !recording, readiness != .warm || !enabled {
                close()
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
            openIfNeeded()
        }
    }

    /// Returns the recording as 16 kHz mono, the format Parakeet expects.
    func stop() throws -> [Float] {
        let (samples, rate) = queue.sync { (finish(), sampleRate) }
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

    private func openIfNeeded() {
        guard engine == nil else { return }
        let engine = AVAudioEngine()
        let format = engine.inputNode.outputFormat(forBus: 0)
        sampleRate = format.sampleRate
        let buffers = buffers
        buffers.withLock { $0.preRollLimit = Int(format.sampleRate * Self.preRollSeconds) }
        let onLevel = onLevel
        engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            guard let channel = buffer.floatChannelData?[0] else { return }
            let chunk = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
            let recording = buffers.withLock { state -> Bool in
                if state.recording {
                    state.captured.append(contentsOf: chunk)
                } else {
                    state.preRoll.append(contentsOf: chunk)
                    let excess = state.preRoll.count - state.preRollLimit
                    if excess > 0 { state.preRoll.removeFirst(excess) }
                }
                return state.recording
            }
            guard recording else { return }
            let rms = (chunk.reduce(0) { $0 + $1 * $1 } / Float(max(chunk.count, 1))).squareRoot()
            DispatchQueue.main.async { onLevel(rms) }
        }
        do {
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            let onError = onError
            DispatchQueue.main.async { onError(error) }
            return
        }
        self.engine = engine
        // A new input device (AirPods connecting) invalidates the running
        // engine. Drop it; the next start opens the new device.
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            self?.queue.async {
                guard let self else { return }
                self.close()
                if self.readiness == .always { self.openIfNeeded() }
            }
        }
    }

    private func close() {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
        configurationObserver = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        buffers.withLock { $0.preRoll = [] }
    }
}
