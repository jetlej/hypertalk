import SwiftUI

/// The push-to-talk key (#42) and hands-free locking, rows in the General section.
struct HotkeyRow: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        PillRow("Hotkey") {
            PillMenu(title: store.current.hotkey.key.displayName) {
                ForEach(HotkeyKey.allCases, id: \.self) { key in
                    Toggle(key.displayName, isOn: Binding(
                        get: { store.current.hotkey.key == key },
                        set: { on in if on { store.update { $0.hotkey.key = key } } }
                    ))
                }
            }
        }
        let key = store.current.hotkey.key.shortName
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
