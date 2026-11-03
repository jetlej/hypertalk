import Foundation

/// Whether the onboarding window has been through (#51).
///
/// The `settings.json` field for this feature; see `Settings`. Give each new
/// field a default and decode it in `init(from:)` with
/// `decodeIfPresent(…) ?? default`, so older files and `{}` still load.
struct OnboardingSettings: Codable, Equatable {
    /// Set by Get Started or by closing the window. Missing in files from
    /// before v0.2.0, so upgraders see the window once too.
    var completed = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        completed = try c.decodeIfPresent(Bool.self, forKey: .completed) ?? false
    }
}

/// What the onboarding window offers and what Get Started saves. Pure, so it
/// is tested; `OnboardingWindow` is the view.
enum Onboarding {
    /// Whether Hypertalk.app opens the window at launch: until the user has been
    /// through it once, and after that only while a grant is missing. A
    /// foreground CLI run asks the old way and shows no window.
    static func showsWindow(isApp: Bool, completed: Bool, state: PermissionState) -> Bool {
        isApp && (!completed || !state.allGranted)
    }

    /// Every key, in the onboarding dropdown's order: fn, then the right-hand
    /// keys, which no shortcut uses, then the left, with Shift last.
    static let hotkeyChoices: [HotkeyKey] = [
        .fn, .rightOption, .rightCommand, .rightControl,
        .leftOption, .leftCommand, .leftControl, .rightShift, .leftShift,
    ]

    /// Languages many people dictate in, offered right after the Mac's own.
    static let commonLanguages = ["en", "es", "fr", "de", "it", "pt", "zh", "ja", "ko", "hi", "ar"]

    /// The Languages menu: the Mac's languages first, then the common ones
    /// not already listed, then every other Whisper language under More
    /// Languages, sorted by `name`. Only codes Whisper knows appear.
    static func languageMenu(
        preferred: [String],
        name: (String) -> String = { SpokenLanguage.displayName($0) }
    ) -> (mac: [String], common: [String], more: [String]) {
        let known = SpokenLanguage.whisperLanguages
        let mac = preferred.filter(known.contains)
        let common = commonLanguages.filter { known.contains($0) && !mac.contains($0) }
        let listed = Set(mac + common)
        let more = known.subtracting(listed).sorted {
            name($0).localizedStandardCompare(name($1)) == .orderedAscending
        }
        return (mac, common, more)
    }

    /// The languages ticked when the window opens: the saved list, or else
    /// the Mac's languages, which is what Hypertalk follows until the user
    /// picks.
    static func initialLanguages(saved: [String]?, preferred: [String]) -> [String] {
        (saved ?? preferred).filter(SpokenLanguage.whisperLanguages.contains)
    }

    /// The pill's title for `names`: "English", "English, Spanish", "English +2".
    static func summary(_ names: [String]) -> String {
        switch names.count {
        case 0: return "None"
        case 1, 2: return names.joined(separator: ", ")
        default: return "\(names[0]) +\(names.count - 1)"
        }
    }

    /// `settings` after Get Started with `hotkey`, `lockMode` and `languages`
    /// picked.
    ///
    /// Ticking exactly the Mac's languages leaves `language.spoken` unset, so
    /// it keeps following the Mac. The model changes only when it can't hear
    /// the languages: any language besides English on an English-only model
    /// switches to multilingual Small. English only keeps the current model,
    /// which for a new user is the recommended Base.
    static func apply(
        hotkey: HotkeyKey,
        custom: CustomHotkey? = nil,
        lockMode: LockMode,
        languages: [String],
        preferred: [String],
        to settings: Settings
    ) -> Settings {
        var next = settings
        next.hotkey.key = hotkey
        next.hotkey.custom = custom
        next.hotkey.lockMode = lockMode
        let mac = preferred.filter(SpokenLanguage.whisperLanguages.contains)
        next.language.spoken = Set(languages) == Set(mac) ? nil : languages
        // The model follows the languages: Parakeet for English or Europe's
        // 25, Whisper Large for the rest. Nil for the recommended model.
        let best = ModelRegistry.best(for: languages)
        next.model.id = best == ModelRegistry.recommended()?.id ? nil : best
        next.onboarding.completed = true
        return next
    }

}
