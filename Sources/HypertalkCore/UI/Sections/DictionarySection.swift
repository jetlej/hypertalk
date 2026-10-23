import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The dictionary (#33): learning words from corrections, the words learned,
/// the example sentence, and the file itself.
struct DictionarySection: View {
    @ObservedObject var store: SettingsStore
    let dictionary: DictionaryStore

    /// The example sentence's language: the chosen one, else English, which
    /// the English-only models and most dictation use.
    private var exampleLanguage: String { store.current.language.code ?? "en" }

    /// Whether the selected model reads the example sentence: Whisper does,
    /// Parakeet takes no prompt.
    private var usesExample: Bool {
        let model = store.current.model.id.flatMap(ModelRegistry.find) ?? ModelRegistry.recommended()
        return model?.engine == .whisperKit
    }

    var body: some View {
        SettingsGroup("Dictionary") {
            SwitchRow(
                "Learn new words",
                caption: "Fix a name or term right after dictating it, and Hypertalk adds it to your dictionary.",
                isOn: Binding(
                    get: { store.current.vocabulary.learnFromCorrections },
                    set: { on in store.update { $0.vocabulary.learnFromCorrections = on } }
                )
            )

            if !store.current.vocabulary.learned.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Learned words")
                    FlowLayout(spacing: 6) {
                        ForEach(store.current.vocabulary.learned, id: \.self) { word in
                            LearnedWordChip(word: word) { forget(word) }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Example sentence (\(SpokenLanguage.displayName(exampleLanguage)))")
                TextField(
                    "I pushed the WhisperKit fix and checked the Vercel dashboard.",
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
                Text(usesExample
                    ? "A sentence you'd say, using your words. Whisper reads it before each dictation to spell them your way; it adds a little time."
                    : "Only Whisper models read this; Parakeet relies on the dictionary's replacements instead.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            PillRow("Words and replacements") {
                Button("Open Dictionary File") { Self.openDictionary() }
                    .buttonStyle(.pill)
            }
        }
    }

    /// Removes a learned word from the dictionary and never learns it again.
    private func forget(_ word: String) {
        dictionary.remove(word: word)
        store.update { settings in
            settings.vocabulary.learned.removeAll { $0 == word }
            if !settings.vocabulary.ignored.contains(word) { settings.vocabulary.ignored.append(word) }
        }
    }

    /// Opens the dictionary in the default plain-text editor, creating it
    /// from the template first if it is missing. The file has no extension,
    /// so `open(_:)` alone would not know what to open it with. If the old
    /// `dictionary.json` is still there, the conversion at launch failed; that
    /// file opens instead, so the problem can be fixed and nothing is left
    /// behind by a new template.
    static func openDictionary() {
        let unconverted = Paths.fileType(Paths.dictionaryFile.path) == nil
            && Paths.fileType(Paths.legacyDictionaryFile.path) != nil
        let file = unconverted ? Paths.legacyDictionaryFile : Paths.dictionaryFile
        if !unconverted { DictionaryStore(file: file).createIfMissing() }
        let editor = NSWorkspace.shared.urlForApplication(toOpen: UTType.plainText)
            ?? URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        NSWorkspace.shared.open([file], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error { Log.warning("couldn't open \(file.path): \(error.localizedDescription)") }
        }
    }

}

/// One learned word, with a button that forgets it.
private struct LearnedWordChip: View {
    let word: String
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(word)
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Remove “\(word)” and don't learn it again")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.primary.opacity(0.08)))
    }
}

/// Lays its children out in rows, wrapping to the next row when one is full.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func rows(width: CGFloat, subviews: Subviews) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        var current: (indices: [Int], width: CGFloat, height: CGFloat) = ([], 0, 0)
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = ([index], size.width, size.height)
            } else {
                current = (current.indices + [index], needed, max(current.height, size.height))
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
