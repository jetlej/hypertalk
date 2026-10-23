import Foundation

enum Engine: String, Codable {
    case whisperKit
    case parakeet
}

package struct TranscriptionModel: Codable {
    package let id: String
    let displayName: String
    let engine: Engine
    /// Engine-specific identifier (e.g. "openai_whisper-base.en" for WhisperKit).
    var whisperKitID: String? = nil
    /// The Parakeet version for `.parakeet`: "v2" (English) or "v3".
    var engineID: String? = nil
    let sizeMB: Int
    let languages: [String]
    let recommended: Bool
}

struct ModelsManifest: Codable {
    let models: [TranscriptionModel]
}
