import Foundation

/// Built-in transcription model registry.
///
/// The model list lives directly in source rather than as a JSON resource so
/// the binary stays self-contained — no `Bundle.module` lookup, no per-target
/// resource bundle to ship alongside the executable.
package enum ModelRegistry {
    static let shared: [TranscriptionModel] = [
        // Parakeet TDT 0.6B: the most accurate and fastest here on English.
        TranscriptionModel(
            id: "parakeet-tdt-v2",
            displayName: "Parakeet v2 (English)",
            engine: .parakeet,
            engineID: "v2",
            sizeMB: 600,
            languages: ["en"],
            recommended: true
        ),
        // v3 hears 25 European languages and detects which on its own.
        TranscriptionModel(
            id: "parakeet-tdt-v3",
            displayName: "Parakeet v3",
            engine: .parakeet,
            engineID: "v3",
            sizeMB: 600,
            languages: ["bg", "hr", "cs", "da", "nl", "en", "et", "fi", "fr", "de", "el", "hu", "it", "lv", "lt", "mt", "pl", "pt", "ro", "sk", "sl", "es", "sv", "ru", "uk"],
            recommended: false
        ),
        TranscriptionModel(
            id: "whisper-base.en",
            displayName: "Whisper Base (English)",
            engine: .whisperKit,
            whisperKitID: "openai_whisper-base.en",
            sizeMB: 145,
            languages: ["en"],
            recommended: false
        ),
        TranscriptionModel(
            id: "whisper-large-v3-turbo",
            displayName: "Whisper Large v3 Turbo",
            engine: .whisperKit,
            whisperKitID: "openai_whisper-large-v3-v20240930_turbo",
            sizeMB: 1620,
            languages: ["multi"],
            recommended: false
        ),
        TranscriptionModel(
            id: "whisper-small.en",
            displayName: "Whisper Small (English)",
            engine: .whisperKit,
            whisperKitID: "openai_whisper-small.en",
            sizeMB: 488,
            languages: ["en"],
            recommended: false
        ),
        TranscriptionModel(
            id: "whisper-small",
            displayName: "Whisper Small",
            engine: .whisperKit,
            whisperKitID: "openai_whisper-small",
            sizeMB: 490,
            languages: ["multi"],
            recommended: false
        ),
    ]

    package static func find(_ id: String) -> TranscriptionModel? {
        shared.first { $0.id == id }
    }

    package static func recommended() -> TranscriptionModel? {
        shared.first { $0.recommended } ?? shared.first
    }
}
