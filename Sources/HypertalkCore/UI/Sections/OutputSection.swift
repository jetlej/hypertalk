import SwiftUI

/// How the transcript reaches the cursor, and the recording pill.
struct OutputSection: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        SettingsGroup("Output") {
            PillRow("Insert text by") {
                PillMenu(title: Self.name(store.current.output.injectMode)) {
                    ForEach(InjectMode.allCases, id: \.self) { mode in
                        Toggle(Self.name(mode), isOn: Binding(
                            get: { store.current.output.injectMode == mode },
                            set: { on in if on { store.update { $0.output.injectMode = mode } } }
                        ))
                    }
                }
            }
            SwitchRow(
                "Paste when focus changes",
                caption: "Off: if you switch apps or fields while dictating, the text goes to the clipboard instead.",
                isOn: Binding(
                    get: { store.current.output.pasteWhenFocusChanges },
                    set: { on in store.update { $0.output.pasteWhenFocusChanges = on } }
                )
            )
            SwitchRow(
                "Show recording pill",
                isOn: Binding(
                    get: { store.current.output.showOverlay },
                    set: { on in store.update { $0.output.showOverlay = on } }
                )
            )
        }
    }

    private static func name(_ mode: InjectMode) -> String {
        switch mode {
        case .paste: return "Pasting"
        case .typeUnicode: return "Typing"
        }
    }
}

/// A label, an optional caption under it, and a switch on the right.
struct SwitchRow: View {
    let label: String
    var caption: String?
    @Binding var isOn: Bool

    init(_ label: String, caption: String? = nil, isOn: Binding<Bool>) {
        self.label = label
        self.caption = caption
        self._isOn = isOn
    }

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 16)
            Toggle(label, isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }
}
