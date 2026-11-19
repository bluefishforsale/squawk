// Owns the CoreML models. Loading is lazy and unloading is explicit because
// the loaded models are nearly all of the app's memory. Parakeet does the
// transcription; a second, smaller CTC model is loaded only when the user has
// listed names, and re-listens to the audio to settle misheard ones.

import FluidAudio
import Foundation
import SquawkCore

actor Transcriber {
    struct Output {
        var text: String
        /// Set when name correction could not run. The text is still usable.
        var warning: String?
    }

    /// FluidAudio rejects anything shorter with `ASRError.invalidAudioData`.
    static let minimumSamples = 4800

    private var manager: AsrManager?
    private var boosting: (names: [NameEntry], session: VocabularyBoostingSession)?

    func prepare() async throws {
        guard manager == nil else { return }
        let cache = AsrModels.defaultCacheDirectory(for: .v3)
        let models: AsrModels
        if AsrModels.modelsExist(at: cache, version: .v3) {
            ModelHub.offlineMode = true
            models = try await AsrModels.loadFromCache(version: .v3)
        } else {
            // NOTE: one of the two network accesses in the app (the other is
            // the name model below). Once the models are on disk every later
            // launch takes the branch above and stays offline.
            ModelHub.offlineMode = false
            models = try await AsrModels.downloadAndLoad(version: .v3)
            ModelHub.offlineMode = true
        }
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        self.manager = manager
    }

    /// Loads the name model too, so the first dictation after launch does not
    /// wait for it.
    func prepare(names: [NameEntry]) async throws {
        try await prepare()
        _ = try await session(for: names)
    }

    func transcribe(_ samples: [Float], names: [NameEntry] = []) async throws -> Output {
        try await prepare()
        guard let manager else { return Output(text: "") }
        var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        let result = try await manager.transcribe(samples, decoderState: &state)

        let session: VocabularyBoostingSession?
        do {
            session = try await self.session(for: names)
        } catch {
            return Output(text: result.text, warning: "Name correction unavailable: \(error.localizedDescription)")
        }
        guard let session else { return Output(text: result.text) }
        let rescored = await session.rescore(
            text: result.text, tokenTimings: result.tokenTimings ?? [], audioSamples: samples)
        return Output(text: rescored?.text ?? result.text)
    }

    func unload() async {
        await manager?.cleanup()
        manager = nil
        boosting = nil
    }

    private func session(for names: [NameEntry]) async throws -> VocabularyBoostingSession? {
        let names = names.filter { !$0.name.isEmpty }
        guard !names.isEmpty else {
            boosting = nil
            return nil
        }
        if let boosting, boosting.names == names { return boosting.session }

        let onDisk = CtcModels.modelsExist(at: CtcModels.defaultCacheDirectory())
        // NOTE: the second network access: a one-time fetch of the 110M CTC
        // model the first time any name is listed.
        ModelHub.offlineMode = onDisk
        defer { ModelHub.offlineMode = true }
        let models = try await CtcModels.downloadAndLoad()

        let terms = names.map { CustomVocabularyTerm(text: $0.name, aliases: $0.aliases) }
        let session = try await VocabularyBoostingSession(
            vocabulary: CustomVocabularyContext(terms: terms), ctcModels: models, config: Self.dictationConfig,
            thresholds: Self.dictationThresholds)
        boosting = (names, session)
        return session
    }

    /// FluidAudio's defaults are tuned for keyword recall and will swap a term
    /// in on acoustic evidence alone. In dictation most sentences contain none
    /// of the listed names, so require the transcript to at least resemble the
    /// name or one of its sound-alikes before the audio is consulted.
    private static let dictationConfig = VocabularyRescorer.Config(
        spotterRescueMinSimilarity: 0.30,
        spotterRescueMultiWordMinSimilarity: 0.50)

    /// How much benefit of the doubt a listed name gets over the word that was
    /// transcribed. FluidAudio's default of 4.5 rewrote a real "Derek" and
    /// "terrace" to "Terrac" in testing; at 1.0 those survive (the name lost
    /// to them acoustically by 2.9 and 1.4) while a spoken "Terrac" misheard
    /// as "Tarek" is still corrected (it won by 0.1 before any bonus).
    /// NOTE: measured on synthesized speech only. Too low and names stop being
    /// fixed; too high and ordinary sound-alike words get replaced.
    private static let dictationThresholds = VocabularyBoostingSession.Thresholds(cbw: 1.0)
}
