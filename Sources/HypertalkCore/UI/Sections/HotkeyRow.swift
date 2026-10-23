import SwiftUI

/// The push-to-talk key (#42) and double-tap to lock, rows in the General section.
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
        SwitchRow(
            "Double-tap to lock",
            caption: "Double-tap \(store.current.hotkey.key.shortName) to keep recording hands-free; press it again to finish.",
            isOn: Binding(
                get: { store.current.hotkey.doubleTapToLock },
                set: { on in store.update { $0.hotkey.doubleTapToLock = on } }
            )
        )
    }
}
