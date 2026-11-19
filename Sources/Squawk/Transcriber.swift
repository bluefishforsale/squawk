// Owns the Parakeet CoreML models. Loading is lazy and unloading is explicit
// because the loaded models are nearly all of the app's memory.

import FluidAudio
import Foundation

actor Transcriber {
    /// FluidAudio rejects anything shorter with `ASRError.invalidAudioData`.
    static let minimumSamples = 4800

    private var manager: AsrManager?

    var isLoaded: Bool { manager != nil }

    func prepare() async throws {
        guard manager == nil else { return }
        let cache = AsrModels.defaultCacheDirectory(for: .v3)
        let models: AsrModels
        if AsrModels.modelsExist(at: cache, version: .v3) {
            ModelHub.offlineMode = true
            models = try await AsrModels.loadFromCache(version: .v3)
        } else {
            // NOTE: the only network access in the app. Once the models are on
            // disk every later launch takes the branch above and stays offline.
            models = try await AsrModels.downloadAndLoad(version: .v3)
            ModelHub.offlineMode = true
        }
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        self.manager = manager
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        try await prepare()
        guard let manager else { return "" }
        var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        return try await manager.transcribe(samples, decoderState: &state).text
    }

    func unload() async {
        await manager?.cleanup()
        manager = nil
    }
}
