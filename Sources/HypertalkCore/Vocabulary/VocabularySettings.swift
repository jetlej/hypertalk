/// Learning new words from corrections (like Wispr Flow's auto-learn).
///
/// The `settings.json` field for this feature; see `Settings`. Give each new
/// field a default and decode it in `init(from:)` with
/// `decodeIfPresent(…) ?? default`, so older files and `{}` still load.
struct VocabularySettings: Codable, Equatable {
    /// Watch the text after each dictation and add a word to the dictionary
    /// when the user corrects one Hypertalk got wrong.
    var learnFromCorrections = true
    /// Words added that way, oldest first, so Settings can list them.
    var learned: [String] = []
    /// Learned words the user removed; never learned again.
    var ignored: [String] = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        learnFromCorrections = try c.decodeIfPresent(Bool.self, forKey: .learnFromCorrections) ?? true
        learned = try c.decodeIfPresent([String].self, forKey: .learned) ?? []
        ignored = try c.decodeIfPresent([String].self, forKey: .ignored) ?? []
    }
}
