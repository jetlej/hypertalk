import SwiftUI

/// The push-to-talk key (#42) or a recorded shortcut, and hands-free
/// locking, rows in the General section.
struct HotkeyRow: View {
    @ObservedObject var store: SettingsStore
    @StateObject private var recorder = ShortcutRecorder()

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Hotkey")
                if recorder.isRecording {
                    Text("Press the keys together. Esc cancels.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 16)
            if recorder.isRecording {
                Text(recorder.prompt)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                    .overlay(Capsule().strokeBorder(Theme.blue, lineWidth: 1.5))
                    .shadow(color: Theme.blue.opacity(0.6), radius: 8)
            } else {
                PillMenu(title: store.current.hotkey.custom?.label ?? store.current.hotkey.key.displayName) {
                    ForEach(HotkeyKey.allCases, id: \.self) { key in
                        Toggle(key.displayName, isOn: Binding(
                            get: { store.current.hotkey.custom == nil && store.current.hotkey.key == key },
                            set: { on in if on { pick(key) } }
                        ))
                    }
                    Divider()
                    if let custom = store.current.hotkey.custom {
                        Toggle("Custom: \(custom.label)", isOn: .constant(true))
                    }
                    Button("Record a Custom Shortcut…", action: record)
                }
            }
        }
        .onDisappear { recorder.stop() }
        let key = store.current.hotkey.shortName
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Hands-free")
                Text(Self.caption(store.current.hotkey.lockMode, key: key))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            PillMenu(title: Self.name(store.current.hotkey.lockMode)) {
                ForEach(LockMode.allCases, id: \.self) { mode in
                    Toggle(Self.name(mode), isOn: Binding(
                        get: { store.current.hotkey.lockMode == mode },
                        set: { on in if on { store.update { $0.hotkey.lockMode = mode } } }
                    ))
                }
            }
        }
    }

    private func pick(_ key: HotkeyKey) {
        store.update {
            $0.hotkey.key = key
            $0.hotkey.custom = nil
        }
    }

    private func record() {
        recorder.start { outcome in
            switch outcome {
            case .key(let key): pick(key)
            case .custom(let custom): store.update { $0.hotkey.custom = custom }
            }
        }
    }

    private static func name(_ mode: LockMode) -> String {
        switch mode {
        case .doubleTap: return "Double-tap"
        case .singleTap: return "Single tap"
        case .off: return "Off"
        }
    }

    private static func caption(_ mode: LockMode, key: String) -> String {
        switch mode {
        case .doubleTap: return "Double-tap \(key) to keep recording without holding it; press it again to finish."
        case .singleTap: return "Tap \(key) once to keep recording without holding it; press it again to finish."
        case .off: return "Only holding \(key) records."
        }
    }
}
