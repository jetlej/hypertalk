import FluidAudio
import Foundation

/// NVIDIA Parakeet TDT through FluidAudio, on the Neural Engine. More
/// accurate than Whisper on English and far faster (Open ASR Leaderboard).
///
/// Takes nothing from `TranscriptionContext`: Parakeet has no prompt, and v3
/// detects the language itself. The dictionary's replacement pass still runs
/// on its output, and learned words land there.
package actor ParakeetTranscriber: ModelTranscriber {
    let modelID: String
    private let model: TranscriptionModel
    private let version: AsrModelVersion
    private var manager: AsrManager?
    /// Set by `unload`: this transcriber was replaced and loads nothing more.
    private var retired = false

    package init(model: TranscriptionModel) {
        self.modelID = model.id
        self.model = model
        self.version = Self.version(of: model)
    }

    /// Downloads the model if it isn't on disk, then loads it. `progress`
    /// gets the download's fraction done, 0 to 1.
    package func warmUp(progress: (@Sendable (Double) -> Void)? = nil) async throws {
        if manager != nil || retired { return }
        Log.info("loading \(model.id)...")
        let directory = try Self.directory(for: version)
        try await AsrModels.download(to: directory, version: version) { p in
            progress?(p.fractionCompleted)
        }
        try Task.checkCancellation()
        let models = try await AsrModels.load(from: directory, version: version)
        let loaded = AsrManager(config: .default)
        try await loaded.loadModels(models)
        // Replaced while loading (a model change during startup): drop it.
        if retired {
            await loaded.cleanup()
            return
        }
        manager = loaded
        Log.info("✓ \(model.id) ready")
    }

    /// Frees the model after a swap to another one. A load still running
    /// finishes and is dropped.
    package func unload() async {
        retired = true
        guard let manager else { return }
        self.manager = nil
        await manager.cleanup()
    }

    package func transcribe(_ audio: [Float], context: TranscriptionContext) async throws -> Transcript {
        if manager == nil { try await warmUp() }
        guard let manager else { throw TranscriberError.notLoaded }
        let started = CFAbsoluteTimeGetCurrent()
        // Parakeet refuses clips under its minimum; trailing silence fills a
        // short one out.
        let minimum = ASRConstants.minimumRequiredSamples(forSampleRate: 16_000)
        let input = audio.count >= minimum ? audio : audio + [Float](repeating: 0, count: minimum - audio.count)
        var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        let result = try await manager.transcribe(input, decoderState: &state)
        let total = CFAbsoluteTimeGetCurrent() - started
        var timings = TranscriberTimings(audioSeconds: Double(audio.count) / 16_000, total: total)
        timings.decoder = total
        timings.language = DictionaryContext.knownLanguage(of: model)
        let text = result.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return Transcript(text: text, timings: timings)
    }

    // MARK: - On disk

    /// True if `model`'s weights are already under `Paths.appSupport`.
    package static func isCached(_ model: TranscriptionModel) -> Bool {
        let version = version(of: model)
        let directory = Paths.appSupport.appendingPathComponent("fluidaudio/\(model.engineID ?? "v3")")
        return AsrModels.modelsExist(at: directory, version: version)
    }

    /// Where FluidAudio keeps a version: `Paths.appSupport/fluidaudio`, never
    /// its default under ~/Library/Application Support/FluidAudio, so
    /// `hypertalk install --uninstall` and the model cache stay in one place.
    private static func directory(for version: AsrModelVersion) throws -> URL {
        let base = try Paths.prepareDirectory(Paths.appSupport)
        let root = try Paths.prepareDirectory(base.appendingPathComponent("fluidaudio"))
        return root.appendingPathComponent(name(of: version))
    }

    private static func version(of model: TranscriptionModel) -> AsrModelVersion {
        model.engineID == "v2" ? .v2 : .v3
    }

    private static func name(of version: AsrModelVersion) -> String {
        version == .v2 ? "v2" : "v3"
    }
}
