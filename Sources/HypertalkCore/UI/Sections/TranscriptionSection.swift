import AppKit
import SwiftUI

/// The model and the spoken language (#43).
struct TranscriptionSection: View {
    @ObservedObject var store: SettingsStore
    /// A model loading behind the one in use, after a change here.
    @ObservedObject private var loading = ModelLoadStatus.shared

    /// Every language Whisper knows, by name in the user's language.
    private static let languages: [(code: String, name: String)] = SpokenLanguage.whisperLanguages
        .map { (code: $0, name: SpokenLanguage.displayName($0)) }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

    private var selectedModel: TranscriptionModel? {
        store.current.model.id.flatMap(ModelRegistry.find) ?? ModelRegistry.recommended()
    }

    var body: some View {
        SettingsGroup("Transcription") {
            languagePicker

            // Built by hand: LabeledContent aligns the menu with the first
            // line, and it should sit centered beside both.
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Model")
                    if let model = selectedModel, loading.current == nil {
                        Text(summary(model))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                PillMenu(title: selectedModel.map(Self.menuTitle) ?? "None") {
                    modelGroup("English", ModelRegistry.shared.filter { !$0.isMultilingual })
                    modelGroup("Multilingual", ModelRegistry.shared.filter(\.isMultilingual))
                }
            }

            if let state = loading.current {
                HStack(spacing: 6) {
                    switch state.phase {
                    case .downloading(let fraction?):
                        ProgressView(value: fraction).frame(width: 80)
                    case .downloading(nil), .loading:
                        ProgressView().controlSize(.small)
                    case .failed:
                        EmptyView()
                    }
                    caption(Self.capitalized(state.text))
                }
            }
        }
    }

    /// One group of the Model menu, smallest first, with a checkmark on the
    /// selected model and a download arrow on each not yet on the Mac.
    @ViewBuilder
    private func modelGroup(_ title: String, _ models: [TranscriptionModel]) -> some View {
        Section(title) {
            ForEach(models.sorted { $0.sizeMB < $1.sizeMB }, id: \.id) { model in
                Toggle(isOn: Binding(
                    get: { selectedModel?.id == model.id },
                    set: { on in if on { store.update { $0.model.id = model.id } } }
                )) {
                    // A model not on the Mac yet downloads when chosen; the
                    // arrow says so without words.
                    if Transcribers.isCached(model) {
                        Text(Self.shortName(model))
                    } else {
                        Label(Self.shortName(model), systemImage: "arrow.down.circle")
                    }
                }
            }
        }
    }

    /// "Whisper Small" for "Whisper Small (English)": the menu's groups say the rest.
    private static func shortName(_ model: TranscriptionModel) -> String {
        model.displayName.replacingOccurrences(of: " (English)", with: "")
    }

    /// The closed menu, where the groups don't show: "Whisper Base (English)".
    private static func menuTitle(_ model: TranscriptionModel) -> String {
        model.isMultilingual ? shortName(model) : "\(shortName(model)) (English)"
    }

    /// How each model trades speed for accuracy, measured with
    /// `hypertalk-bench transcription` on an M4 Pro (#43).
    private static let tradeOff: [String: String] = [
        "parakeet-tdt-v2": "Most accurate, fastest",
        "parakeet-tdt-v3": "Accurate, fast",
        "whisper-base.en": "Fast, least accurate",
        "whisper-small.en": "More accurate, slower",
        "whisper-small": "Fast",
        "whisper-large-v3-turbo": "Accurate, slowest",
    ]

    /// "Fastest · English only · 145 MB". Not shown while the model loads:
    /// the progress line under the menu says that instead.
    private func summary(_ model: TranscriptionModel) -> String {
        let languages = model.languages.contains("multi") ? "99 languages"
            : model.isMultilingual ? "\(model.languages.count) languages" : "English only"
        let size = model.sizeMB >= 1000
            ? String(format: "%.1f GB", Double(model.sizeMB) / 1000)
            : "\(model.sizeMB) MB"
        return [Self.tradeOff[model.id], languages, size]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private static func capitalized(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }

    /// Automatic, then every language by name. Choosing one switches to the
    /// best model for it (`ModelRegistry.best`). A saved code Whisper does
    /// not know shows as Automatic, which is how it is treated.
    @ViewBuilder private var languagePicker: some View {
        let code = store.current.language.code?.lowercased()
        let selected = code.flatMap { SpokenLanguage.whisperLanguages.contains($0) ? $0 : nil }
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Language you speak")
                caption("The model switches to the best one for it.")
            }
            Spacer()
            PillMenu(title: selected.map { SpokenLanguage.displayName($0) } ?? "Automatic") {
                languageToggle("Automatic", nil, selected: selected)
                Divider()
                ForEach(Self.languages, id: \.code) { language in
                    languageToggle(language.name, language.code, selected: selected)
                }
            }
        }

        if store.current.language.code == nil {
            PillRow("Automatic chooses from") {
                SpokenLanguagesButton(store: store)
            }
        }
    }

    private func languageToggle(_ name: String, _ code: String?, selected: String?) -> some View {
        Toggle(name, isOn: Binding(
            get: { selected == code },
            set: { on in
                guard on else { return }
                store.update { settings in
                    settings.language.code = code
                    settings.model.id = Self.bestModel(for: settings.language)
                }
            }
        ))
    }

    /// The best model for a Language setting: its one language, or with
    /// Automatic, the languages it chooses from.
    static func bestModel(for language: LanguageSettings) -> String {
        ModelRegistry.best(for: language.code.map { [$0] } ?? language.spokenOrPreferred)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

/// The languages Automatic chooses among, as a pill that opens checkboxes.
/// Starts from the Mac's preferred languages; the first edit saves the list
/// to settings.json.
private struct SpokenLanguagesButton: View {
    @ObservedObject var store: SettingsStore
    @State private var isOpen = false

    private var spoken: [String] {
        store.current.language.spokenOrPreferred.filter(SpokenLanguage.whisperLanguages.contains)
    }

    var body: some View {
        Button { isOpen.toggle() } label: {
            PillLabel(title: Onboarding.summary(spoken.map { SpokenLanguage.displayName($0) }), chevron: true)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            SpokenLanguagesList(store: store)
        }
    }
}

/// The popover's content, observing the store so ticks show as they change.
private struct SpokenLanguagesList: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        let spoken = store.current.language.spokenOrPreferred.filter(SpokenLanguage.whisperLanguages.contains)
        LanguageChecklist(ticked: spoken, toggle: { code in
            var next = spoken.filter { $0 != code }
            if !spoken.contains(code) { next.append(code) }
            // Keep at least one: an empty list trusts nothing.
            guard !next.isEmpty else { return }
            store.update { settings in
                settings.language.spoken = next
                settings.model.id = TranscriptionSection.bestModel(for: settings.language)
            }
        }) {
            if store.current.language.spoken != nil {
                Divider().padding(.vertical, 2)
                Button("Use the Mac's Languages") {
                    store.update { settings in
                        settings.language.spoken = nil
                        settings.model.id = TranscriptionSection.bestModel(for: settings.language)
                    }
                }
                    .buttonStyle(.link)
            }
        }
    }
}
