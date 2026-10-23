import AppKit
import ApplicationServices

/// Learns new words from the user's corrections, like Wispr Flow's
/// auto-learn: fix "ver cell" to "Vercel" right after dictating it, and
/// "Vercel" joins the dictionary with "ver cell" as what it replaces.
///
/// After a transcript is inserted, the learner reads the field it went into
/// over Accessibility every `pollInterval`, for up to `watchDuration` or
/// until focus leaves the field or the next dictation starts. It keeps the
/// corrections from the last reading that still matched (`CorrectionDiff`),
/// so a chat field cleared by sending still counts the fix made before it.
/// Field text stays in memory for the watch only and is never logged or
/// written; only the learned word reaches the dictionary file.
@MainActor
final class VocabularyLearner {
    static let pollInterval: TimeInterval = 0.3
    static let watchDuration: TimeInterval = 45
    /// Fields longer than this (in UTF-16 units) are not watched: a long
    /// document is slow to read on every poll.
    static let maxFieldLength = 20_000
    /// Polls to wait for a paste to land before giving up on a field.
    static let locateAttempts = 6

    private let settings: SettingsStore
    private let dictionary: DictionaryStore
    /// Called with each word learned, to tell the user.
    var onLearned: ((String) -> Void)?

    private struct Watch {
        let element: FocusedElement
        let pid: pid_t?
        let dictated: String
        let started: TimeInterval
        /// The field right after the dictation landed, and where it is.
        var before: [Character]?
        var span: Range<Int>?
        var latest: [Correction] = []
        var attempts = 0
    }

    private var watched: Watch?
    private var timer: Timer?

    init(settings: SettingsStore, dictionary: DictionaryStore) {
        self.settings = settings
        self.dictionary = dictionary
    }

    /// Starts watching `element`, where `text` was just inserted. Ends any
    /// earlier watch first.
    func watch(_ element: FocusedElement, pid: pid_t?, text: String) {
        finish(notify: true)
        guard settings.current.vocabulary.learnFromCorrections else { return }
        let dictated = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !dictated.isEmpty else { return }
        watched = Watch(element: element, pid: pid, dictated: dictated, started: ProcessInfo.processInfo.systemUptime)
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func poll() {
        guard let watch = watched else { return }
        if ProcessInfo.processInfo.systemUptime - watch.started > Self.watchDuration {
            finish(notify: true)
            return
        }
        guard read() else { return }
        let focus = FocusSnapshot.capture()
        if focus.pid != watch.pid || focus.element != watch.element {
            finish(notify: true)
        }
    }

    /// Reads the field once and updates the watch. Returns false if the
    /// watch ended.
    @discardableResult
    private func read() -> Bool {
        guard var watch = watched else { return false }
        guard let value = watch.element.value(maxLength: Self.maxFieldLength) else {
            stop()
            return false
        }
        let chars = Array(value)
        if let before = watch.before, let span = watch.span {
            if let found = CorrectionDiff.corrections(before: before, span: span, after: chars) {
                watch.latest = found
            }
        } else if let span = Self.locate(watch.dictated, in: value) {
            watch.before = chars
            watch.span = span
        } else {
            watch.attempts += 1
            if watch.attempts >= Self.locateAttempts {
                stop()
                return false
            }
        }
        watched = watch
        return true
    }

    /// Ends the watch and learns from its last good reading. `notify`: tell
    /// the user; false when a new dictation is starting, so the message does
    /// not cover its recording pill.
    func finish(notify: Bool) {
        guard watched?.before != nil else {
            stop()
            return
        }
        read()
        let corrections = watched?.latest ?? []
        stop()
        guard settings.current.vocabulary.learnFromCorrections else { return }

        let vocabulary = settings.current.vocabulary
        var known = Set(dictionary.current().dictionary.vocabulary.map { $0.lowercased() })
        known.formUnion(vocabulary.ignored.map { $0.lowercased() })
        for correction in corrections where CorrectionDiff.isLearnable(correction, isKnownWord: Self.isKnownWord) {
            let word = correction.corrected
            guard known.insert(word.lowercased()).inserted else { continue }
            learn(correction)
            if notify { onLearned?(word) }
        }
    }

    private func learn(_ correction: Correction) {
        let word = correction.corrected
        let heard = correction.heard
        // A casing fix needs no Replaces: the word itself is the canonical spelling.
        let replaces = heard.lowercased() == word.lowercased() || heard.contains(",") ? [] : [heard]
        guard dictionary.append(word: word, replaces: replaces) else { return }
        settings.update { settings in
            if !settings.vocabulary.learned.contains(word) { settings.vocabulary.learned.append(word) }
        }
        // The log never carries text, learned words included.
        Log.info("vocabulary: learned a word from a correction")
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        watched = nil
    }

    /// Where `dictated` sits in `value`, as Character offsets: the last
    /// occurrence, which is the one just inserted at the cursor.
    nonisolated static func locate(_ dictated: String, in value: String) -> Range<Int>? {
        guard let range = value.range(of: dictated, options: .backwards) else { return nil }
        let start = value.distance(from: value.startIndex, to: range.lowerBound)
        return start ..< start + dictated.count
    }

    /// In the system spelling dictionary, and not a word the user taught it.
    private static func isKnownWord(_ word: String) -> Bool {
        let checker = NSSpellChecker.shared
        if checker.hasLearnedWord(word) { return false }
        let miss = checker.checkSpelling(of: word, startingAt: 0, language: nil, wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)
        return miss.location == NSNotFound
    }
}

extension VocabularyLearner: DictationObserver {
    func dictationStarted() {
        finish(notify: false)
    }
}

extension FocusedElement {
    /// The element's text, or nil if it has none or is longer than
    /// `maxLength` UTF-16 units. Call after `FocusSnapshot.capture()`, which
    /// sets the Accessibility timeout, and never on a secure field.
    func value(maxLength: Int) -> String? {
        var count: CFTypeRef?
        if AXUIElementCopyAttributeValue(ref, kAXNumberOfCharactersAttribute as CFString, &count) == .success,
           let count = count as? Int, count > maxLength {
            return nil
        }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ref, kAXValueAttribute as CFString, &value) == .success,
              let text = value as? String, text.utf16.count <= maxLength
        else { return nil }
        return text
    }
}
