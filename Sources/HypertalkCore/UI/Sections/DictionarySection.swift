import AppKit
import SwiftUI

/// The dictionary (#33), edited in place: each word, spelled the way the
/// user wants, and what the model writes instead. Saved to the same
/// plain-text file (`DictionaryStore`), which the learner appends to and the
/// replacement pass reads. Also learning from corrections, and Whisper's
/// spelling hint.
struct DictionarySection: View {
    @ObservedObject var store: SettingsStore
    let dictionary: DictionaryStore

    /// One row of the editor.
    struct Entry: Identifiable, Equatable {
        let id = UUID()
        var word: String
        /// Comma-separated, as typed.
        var replaces: String
    }

    @State private var entries: [Entry] = []
    @State private var loaded = false
    /// A save waiting for typing to pause.
    @State private var pendingSave: DispatchWorkItem?

    /// The spelling hint's language: the chosen one, else English, which the
    /// English-only models and most dictation use.
    private var exampleLanguage: String { store.current.language.code ?? "en" }

    /// Whether the selected model reads the spelling hint: Whisper does,
    /// Parakeet takes no prompt.
    private var usesExample: Bool {
        let model = store.current.model.id.flatMap(ModelRegistry.find) ?? ModelRegistry.recommended()
        return model?.engine == .whisperKit
    }

    var body: some View {
        SettingsGroup("Dictionary") {
            SwitchRow(
                "Learn new words",
                caption: "Fix a name or term right after dictating it, and Hypertalk adds it here.",
                isOn: Binding(
                    get: { store.current.vocabulary.learnFromCorrections },
                    set: { on in store.update { $0.vocabulary.learnFromCorrections = on } }
                )
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Word").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Replaces").frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear.frame(width: 22, height: 1)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

                ForEach($entries) { $entry in
                    HStack(spacing: 8) {
                        HStack(spacing: 6) {
                            TextField("Word", text: $entry.word)
                            if isLearned(entry.word) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.ice)
                                    .help("Learned from a correction")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        TextField("What it hears instead", text: $entry.replaces)
                            .frame(maxWidth: .infinity)
                        Button { remove(entry) } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .frame(width: 22)
                        .help("Remove")
                    }
                    .textFieldStyle(.roundedBorder)
                }

                Button {
                    entries.append(Entry(word: "", replaces: ""))
                } label: {
                    Label("Add Word", systemImage: "plus")
                }
                .buttonStyle(.pill)
                .padding(.top, 4)

                Text("Hypertalk writes each word exactly as spelled here, and swaps in the word wherever it hears anything under Replaces (separate them with commas).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Only Whisper reads it (as the speech before yours); Parakeet,
            // the default, has no such input, so the field is hidden there.
            if usesExample {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Spelling hint (\(SpokenLanguage.displayName(exampleLanguage)))")
                    TextField(
                        "A sentence you'd say, using your names and terms",
                        text: Binding(
                            get: { store.current.dictionary.examples[exampleLanguage] ?? "" },
                            set: { text in
                                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                                store.update { $0.dictionary.examples[exampleLanguage] = trimmed.isEmpty ? nil : text }
                            }
                        ),
                        axis: .vertical
                    )
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
                    Text("Write one sentence the way you'd say it, using the names and terms you want spelled right. Whisper reads it before each dictation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onAppear(perform: reload)
        // A word learned while the window is open shows up at once.
        .onChange(of: store.current.vocabulary.learned) { _, _ in reload() }
        .onChange(of: entries) { _, _ in scheduleSave() }
    }

    private func isLearned(_ word: String) -> Bool {
        store.current.vocabulary.learned.contains(word)
    }

    /// Reads the file into the rows, or the first time, shows what is there.
    private func reload() {
        pendingSave?.cancel()
        entries = Self.entries(from: dictionary.current().dictionary)
        loaded = true
    }

    /// Saves after typing pauses, so the file isn't rewritten per keystroke.
    private func scheduleSave() {
        guard loaded else { return }
        pendingSave?.cancel()
        let snapshot = entries
        let save = DispatchWorkItem { [dictionary] in
            let next = Self.dictionary(from: snapshot)
            // Opening Settings changes nothing; only an edit rewrites the file.
            let current = dictionary.current().dictionary
            guard next.terms != current.terms || next.replacements != current.replacements else { return }
            dictionary.save(next)
        }
        pendingSave = save
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: save)
    }

    /// Removes a row. A learned word is also never learned again.
    private func remove(_ entry: Entry) {
        entries.removeAll { $0.id == entry.id }
        let word = entry.word
        guard isLearned(word) else { return }
        store.update { settings in
            settings.vocabulary.learned.removeAll { $0 == word }
            if !settings.vocabulary.ignored.contains(word) { settings.vocabulary.ignored.append(word) }
        }
    }

    // MARK: - Rows and the dictionary

    /// One row per word, in file order: every term, then any replacement
    /// target that isn't one; replacements to the same word share its row.
    static func entries(from dictionary: UserDictionary) -> [Entry] {
        var order: [String] = []
        var from: [String: [String]] = [:]
        for term in dictionary.terms where from[term] == nil {
            order.append(term)
            from[term] = []
        }
        for replacement in dictionary.replacements {
            if from[replacement.to] == nil { order.append(replacement.to) }
            from[replacement.to, default: []] += replacement.from
        }
        return order.map { Entry(word: $0, replaces: (from[$0] ?? []).joined(separator: ", ")) }
    }

    /// The rows as a dictionary. Blank words are skipped; commas can't be in
    /// a word, which the file uses to separate replacements.
    static func dictionary(from entries: [Entry]) -> UserDictionary {
        var result = UserDictionary()
        for entry in entries {
            let word = entry.word.replacingOccurrences(of: ",", with: " ").trimmingCharacters(in: .whitespaces)
            guard !word.isEmpty else { continue }
            result.terms.append(word)
            let replaces = entry.replaces.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if !replaces.isEmpty { result.replacements.append(.init(from: replaces, to: word)) }
        }
        return result
    }
}
