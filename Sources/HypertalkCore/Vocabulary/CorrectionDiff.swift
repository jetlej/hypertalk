import Foundation

/// A word the user fixed by hand right after it was dictated: what Hypertalk
/// wrote and what the user changed it to.
struct Correction: Equatable {
    /// One to three words as transcribed, e.g. "ver cell".
    var heard: String
    /// One or two words as the user spelled them, e.g. "Vercel".
    var corrected: String
}

/// Finds and judges corrections. Pure, so it is tested without a text field.
///
/// The learner reads the field once right after a dictation is inserted
/// (`before`, with the dictated text at `span`) and again later (`after`).
/// Text before and after the dictation must be unchanged; inside it, a
/// word-level diff turns each run of replaced words into a `Correction`.
/// Words only added or only deleted are edits, not corrections, and are
/// ignored, so continuing to type after a dictation learns nothing.
enum CorrectionDiff {
    /// Largest run of transcribed words one correction may replace.
    static let maxHeardWords = 3
    /// Largest run of words one correction may produce.
    static let maxCorrectedWords = 2
    /// How alike, 0…1, the heard and corrected letters must be: below it, the
    /// user rewrote the sentence rather than fixed a misheard word.
    static let minSimilarity = 0.34

    /// The corrections in `after`, or nil when it can't be compared with
    /// `before`: text outside the dictation changed, or the dictation is gone
    /// (a chat field cleared by sending, say).
    static func corrections(before: [Character], span: Range<Int>, after: [Character]) -> [Correction]? {
        guard span.lowerBound >= 0, span.upperBound <= before.count, !span.isEmpty else { return nil }
        let head = before[..<span.lowerBound]
        let tail = before[span.upperBound...]
        guard after.count >= head.count + tail.count,
              after.starts(with: head),
              after.suffix(tail.count).elementsEqual(tail)
        else { return nil }
        let region = after[head.count ..< after.count - tail.count]
        let old = words(String(before[span]))
        let new = words(String(region))
        guard !new.isEmpty else { return nil }
        return hunks(old, new).compactMap { heard, corrected in
            guard (1...maxHeardWords).contains(heard.count),
                  (1...maxCorrectedWords).contains(corrected.count)
            else { return nil }
            return Correction(heard: heard.joined(separator: " "), corrected: corrected.joined(separator: " "))
        }
    }

    /// Whether `correction` names something worth adding to the dictionary:
    /// a name or term, not a typo fix, a rewrite or an everyday word.
    /// `isKnownWord` says whether a word is in the system's spelling
    /// dictionary.
    static func isLearnable(_ correction: Correction, isKnownWord: (String) -> Bool) -> Bool {
        let heard = correction.heard
        let corrected = correction.corrected
        guard heard != corrected, (2...40).contains(corrected.count) else { return false }
        let parts = corrected.split(separator: " ").map(String.init)
        guard parts.allSatisfy(isWordLike) else { return false }

        let sameLetters = heard.lowercased() == corrected.lowercased()
        if sameLetters {
            // Only casing changed: learn "GitHub" or "iPhone", not a
            // capitalized first letter.
            return parts.contains(where: hasInnerCapital)
        }
        guard similarity(letters(heard), letters(corrected)) >= minSimilarity else { return false }
        // Everyday words (and common first names) are already spelled right
        // by the model; a word only the user knows is not in the dictionary.
        return !parts.allSatisfy { isKnownWord($0) && !hasInnerCapital($0) }
    }

    // MARK: - Words

    /// Words split on whitespace, with punctuation stripped from their ends,
    /// so "Versailles," and "Versailles" compare equal.
    static func words(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).compactMap { raw in
            let word = raw.trimmingCharacters(in: .punctuationCharacters.union(.symbols))
            return word.isEmpty ? nil : word
        }
    }

    /// Letters, digits, and the joiners names use (O'Brien, Jean-Luc, AT&T),
    /// with at least one letter: no paths, addresses, code or numbers.
    private static func isWordLike(_ word: String) -> Bool {
        let joiners: Set<Character> = ["'", "’", "-", "&"]
        guard word.contains(where: \.isLetter) else { return false }
        return word.allSatisfy { $0.isLetter || $0.isNumber || joiners.contains($0) }
    }

    private static func hasInnerCapital(_ word: String) -> Bool {
        word.dropFirst().contains(where: \.isUppercase)
    }

    private static func letters(_ text: String) -> [Character] {
        Array(text.lowercased().filter(\.isLetter))
    }

    /// 1 minus the edit distance over the longer length.
    static func similarity(_ a: [Character], _ b: [Character]) -> Double {
        let longest = max(a.count, b.count)
        guard longest > 0 else { return 1 }
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in stride(from: 1, through: b.count, by: 1) {
                current[j] = a[i - 1] == b[j - 1]
                    ? previous[j - 1]
                    : 1 + min(previous[j - 1], previous[j], current[j - 1])
            }
            previous = current
        }
        return 1 - Double(previous[b.count]) / Double(longest)
    }

    /// Runs of replaced words, from a longest-common-subsequence diff:
    /// each pairs the deleted words with the inserted words between the same
    /// two unchanged ones. Runs that only delete or only insert are dropped.
    private static func hunks(_ old: [String], _ new: [String]) -> [(heard: [String], corrected: [String])] {
        let n = old.count, m = new.count
        var lcs = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                lcs[i][j] = old[i] == new[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }
        var result: [(heard: [String], corrected: [String])] = []
        var deleted: [String] = [], inserted: [String] = []
        func flush() {
            if !deleted.isEmpty, !inserted.isEmpty { result.append((deleted, inserted)) }
            deleted = []
            inserted = []
        }
        var i = 0, j = 0
        while i < n || j < m {
            if i < n, j < m, old[i] == new[j] {
                flush()
                i += 1
                j += 1
            } else if j < m, i == n || lcs[i][j + 1] >= lcs[i + 1][j] {
                inserted.append(new[j])
                j += 1
            } else {
                deleted.append(old[i])
                i += 1
            }
        }
        flush()
        return result
    }
}
