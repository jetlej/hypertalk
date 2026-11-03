import Carbon.HIToolbox
import CoreGraphics

/// A key combo, such as ⌃⌥Space, registered with macOS through
/// `RegisterEventHotKey`. macOS reports only this combo's press and release,
/// never any other keystroke, and keeps the combo from reaching the focused
/// app, so a custom shortcut needs no wider event tap (`HotkeyMonitor`).
///
/// Callbacks arrive on the main thread, from the application event loop.
final class CarbonHotKey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let onPress: () -> Void
    private let onRelease: () -> Void

    /// Nil when macOS refuses the combo, such as one another app holds.
    init?(keyCode: UInt32, modifiers: CGEventFlags, onPress: @escaping () -> Void, onRelease: @escaping () -> Void) {
        self.onPress = onPress
        self.onRelease = onRelease

        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<CarbonHotKey>.fromOpaque(userData).takeUnretainedValue()
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard id.signature == CarbonHotKey.signature else { return OSStatus(eventNotHandledErr) }
            if GetEventKind(event) == UInt32(kEventHotKeyPressed) { hotKey.onPress() } else { hotKey.onRelease() }
            return noErr
        }, types.count, &types, userData, &handler)
        guard installed == noErr else { return nil }

        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(keyCode, Self.carbonModifiers(modifiers), id, GetApplicationEventTarget(), 0, &hotKey)
        guard status == noErr else {
            if let handler { RemoveEventHandler(handler) }
            return nil
        }
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }

    /// "HTlk": tells our hot key's events from any other's.
    fileprivate static let signature: OSType = 0x48_54_6C_6B

    static func carbonModifiers(_ flags: CGEventFlags) -> UInt32 {
        var carbon = 0
        if flags.contains(.maskCommand) { carbon |= cmdKey }
        if flags.contains(.maskAlternate) { carbon |= optionKey }
        if flags.contains(.maskControl) { carbon |= controlKey }
        if flags.contains(.maskShift) { carbon |= shiftKey }
        return UInt32(carbon)
    }
}
