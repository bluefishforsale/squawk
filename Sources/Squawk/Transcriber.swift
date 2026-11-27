// Owns the CoreML models. Loading is lazy and unloading is explicit because
// the loaded models are nearly all of the app's memory. Parakeet does the
// transcription; a second, smaller CTC model is loaded only when the user has
// listed names, and re-listens to the audio to settle misheard ones.

import FluidAudio
import Foundation
import SquawkCore

enum ModelInstallError: LocalizedError {
    case busy
    case badRevision
    case failedProbe

    var errorDescription: String? {
        switch self {
        case .busy: "A speech model update is already in progress."
        case .badRevision: "That is not a model revision."
        case .failedProbe: "The new speech model failed its test. The current one was kept."
        }
    }
}

actor Transcriber {
    struct Output {
        var text: String
        /// Set when name correction could not run. The text is still usable.
        var warning: String?
    }

    /// FluidAudio rejects anything shorter with `ASRError.invalidAudioData`.
    static let minimumSamples = 4800
    /// 0.3 s at 16 kHz.
    private static let trailingSilence = 4800

    private var manager: AsrManager?
    /// True while a model update is downloading. The model in use stays
    /// loaded for that whole time: a reload would be checked against the
    /// revision being installed and fail.
    private var isInstalling = false
    private var boosting: (names: [NameEntry], session: VocabularyBoostingSession)?

    func prepare() async throws {
        guard manager == nil else { return }
        guard !isInstalling else { throw ModelInstallError.busy }
        let active = ModelStore.active
        ModelStore.expect(revision: active.revision)
        let models: AsrModels
        if AsrModels.modelsExist(at: active.directory, version: .v3) {
            ModelHub.offlineMode = true
            models = try await AsrModels.load(from: active.directory, version: .v3)
        } else {
            // NOTE: the first-launch download. Once the models are on disk
            // every later launch takes the branch above and stays offline.
            ModelHub.offlineMode = false
            models = try await AsrModels.downloadAndLoad(version: .v3)
            ModelHub.offlineMode = true
        }
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        self.manager = manager
    }

    /// Downloads the speech model at `revision` into its own folder, proves
    /// it can transcribe, and only then switches to it. Dictation keeps
    /// working on the current model throughout, and a failure leaves
    /// everything as it was.
    func install(revision: String, progress: @escaping @Sendable (Double) -> Void) async throws {
        guard ModelStore.isRevision(revision) else { throw ModelInstallError.badRevision }
        guard !isInstalling else { throw ModelInstallError.busy }
        try await prepare()
        isInstalling = true
        let previous = ModelStore.active.revision
        let directory = ModelStore.directory(forRevision: revision)
        ModelStore.expect(revision: revision)
        ModelHub.offlineMode = false
        defer {
            ModelHub.offlineMode = true
            isInstalling = false
        }
        do {
            let models = try await AsrModels.downloadAndLoad(
                to: directory, version: .v3, progressHandler: { progress($0.fractionCompleted) })
            let candidate = AsrManager(config: .default)
            try await candidate.loadModels(models)
            try await Self.proveItTranscribes(candidate)
            await manager?.cleanup()
            manager = candidate
            ModelStore.revision = revision
            ModelStore.removeUpdates(except: revision)
        } catch {
            ModelStore.expect(revision: previous)
            try? FileManager.default.removeItem(at: directory.deletingLastPathComponent())
            throw error
        }
    }

    /// A model can load and still be useless, so it has to turn a known
    /// sentence, spoken by the system voice, back into text containing its
    /// key word. If the system voice is unavailable the check is skipped.
    private static func proveItTranscribes(_ candidate: AsrManager) async throws {
        let clip = FileManager.default.temporaryDirectory.appendingPathComponent("squawk-probe-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: clip) }
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-o", clip.path, "--data-format=LEI16@16000", "This is a test of the speech model."]
        guard (try? say.run()) != nil else { return }
        say.waitUntilExit()
        guard say.terminationStatus == 0,
            let samples = try? AudioConverter().resampleAudioFile(clip), samples.count >= minimumSamples
        else { return }
        var state = TdtDecoderState.make(decoderLayers: await candidate.decoderLayerCount)
        let padded = samples + [Float](repeating: 0, count: trailingSilence)
        let text = try await candidate.transcribe(padded, decoderState: &state).text
        guard text.lowercased().contains("test") else { throw ModelInstallError.failedProbe }
    }

    /// Loads the name model too, so the first dictation after launch does not
    /// wait for it.
    func prepare(names: [NameEntry]) async throws {
        try await prepare()
        _ = try await session(for: names)
    }

    func transcribe(_ samples: [Float], names: [NameEntry] = []) async throws -> Output {
        try await prepare()
        // Audio that stops dead makes the decoder emit nothing for short
        // clips; a little silence after it lets the last word close.
        let samples = samples + [Float](repeating: 0, count: Self.trailingSilence)
        guard let manager else { return Output(text: "") }
        var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        let result = try await manager.transcribe(samples, decoderState: &state)

        // NOTE: spoken hostnames are joined only after rescoring. Joining
        // changes the word count, and the rescorer lines words up with the
        // decoder's token timings.
        func finished(_ text: String) -> String {
            NameEntry.correctingAddresses(in: SpokenHostname.joining(text), names: names)
        }
        let session: VocabularyBoostingSession?
        do {
            session = try await self.session(for: names)
        } catch {
            return Output(
                text: SpokenHostname.joining(result.text),
                warning: "Name correction unavailable: \(error.localizedDescription)")
        }
        let heard = NameEntry.correctingAddresses(in: result.text, names: names)
        guard let session else { return Output(text: finished(heard)) }
        let rescored = await session.rescore(
            text: heard, tokenTimings: result.tokenTimings ?? [], audioSamples: samples)
        guard let rescored,
            !rescored.replacements.contains(where: { $0.shouldReplace && NameEntry.isAddress($0.originalWord) })
        else { return Output(text: finished(heard)) }
        return Output(text: finished(rescored.text))
    }

    func unload() async {
        guard !isInstalling else { return }
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
        // A model update in progress owns the offline switch.
        if !isInstalling { ModelHub.offlineMode = onDisk }
        defer { if !isInstalling { ModelHub.offlineMode = true } }
        let models = try await CtcModels.downloadAndLoad()

        let terms = names.map { CustomVocabularyTerm(text: $0.name, aliases: $0.rescoringAliases) }
        let session = try await VocabularyBoostingSession(
            vocabulary: CustomVocabularyContext(terms: terms), ctcModels: models, config: Self.dictationConfig,
            thresholds: Self.dictationThresholds)
        boosting = (names, session)
        return session
    }

    /// FluidAudio's defaults are tuned for keyword recall and will swap a term
    /// in on acoustic evidence alone. In dictation most sentences contain none
    /// of the listed names, so a name only replaces words that resemble it or
    /// one of its sound-alikes. The spotter rescue that skips that check is
    /// off: it turned "terrace" into "Terrac" and swallowed multi-word spans
    /// like "Terek Skeens" into one name.
    private static let dictationConfig = VocabularyRescorer.Config(spotterRescueEnabled: false)

    /// How much benefit of the doubt a listed name gets over the word that was
    /// transcribed. FluidAudio's default of 4.5 rewrote a real "Derek" and
    /// "terrace" to "Terrac" in testing; at 1.0 those survive (the name lost
    /// to them acoustically by 2.9 and 1.4) while a spoken "Terrac" misheard
    /// as "Tarek" is still corrected (it won by 0.1 before any bonus).
    /// NOTE: measured on synthesized speech only. Too low and names stop being
    /// fixed; too high and ordinary sound-alike words get replaced.
    ///
    /// The similarity floor of 1.0 means a word is only a candidate when it
    /// is spelled exactly like the name or a listed sound-alike, ignoring
    /// case. Misheard names come back as a listed spelling, while the false
    /// hits were mere resemblance: "Terra" for "terrace" at 0.83 and "Merge"
    /// at 0.40. A new mishearing is fixed by training it, never by guessing.
    private static let dictationThresholds = VocabularyBoostingSession.Thresholds(cbw: 1.0, minSimilarity: 1.0)
}
