/// How a finished transcript reaches the cursor, and the recording pill.
///
/// The `settings.json` field for this feature; see `Settings`. Give each new
/// field a default and decode it in `init(from:)` with
/// `decodeIfPresent(…) ?? default`, so older files and `{}` still load.
struct OutputSettings: Codable, Equatable {
    /// Paste (borrows the clipboard and restores it) or type the text. An
    /// unknown name decodes to paste.
    var injectMode: InjectMode = .paste
    /// Paste even when focus moved to another app or field during the
    /// dictation. Off: the transcript is left on the clipboard instead.
    var pasteWhenFocusChanges = false
    /// Show the recording pill at the bottom of the screen.
    var showOverlay = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let mode = try c.decodeIfPresent(String.self, forKey: .injectMode)
        injectMode = mode.flatMap(InjectMode.init(rawValue:)) ?? .paste
        pasteWhenFocusChanges = try c.decodeIfPresent(Bool.self, forKey: .pasteWhenFocusChanges) ?? false
        showOverlay = try c.decodeIfPresent(Bool.self, forKey: .showOverlay) ?? true
    }
}
