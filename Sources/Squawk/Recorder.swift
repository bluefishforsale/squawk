// Captures the microphone only between start and stop, so the macOS mic
// indicator is lit only while the user is actually dictating.

import AVFoundation
import FluidAudio
import os

final class Recorder {
    /// Called on the main queue with the RMS amplitude of each captured
    /// buffer, for the level meter.
    var onLevel: (Float) -> Void = { _ in }

    private var engine: AVAudioEngine?
    private var sampleRate = 0.0
    private let captured = OSAllocatedUnfairLock(initialState: [Float]())

    func start() throws {
        cancel()
        // A fresh engine per recording picks up whatever input device is
        // current; a long-lived one throws after AirPods connect or disconnect.
        let engine = AVAudioEngine()
        let format = engine.inputNode.outputFormat(forBus: 0)
        sampleRate = format.sampleRate
        let captured = captured
        let onLevel = onLevel
        engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            guard let channel = buffer.floatChannelData?[0] else { return }
            let chunk = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
            captured.withLock { $0.append(contentsOf: chunk) }
            let rms = (chunk.reduce(0) { $0 + $1 * $1 } / Float(max(chunk.count, 1))).squareRoot()
            DispatchQueue.main.async { onLevel(rms) }
        }
        try engine.start()
        self.engine = engine
    }

    /// Returns the recording as 16 kHz mono, the format Parakeet expects.
    func stop() throws -> [Float] {
        let samples = drain()
        guard !samples.isEmpty else { return [] }
        return try AudioConverter().resample(samples, from: sampleRate)
    }

    func cancel() {
        _ = drain()
    }

    private func drain() -> [Float] {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        return captured.withLock { samples in
            defer { samples = [] }
            return samples
        }
    }
}
