#if os(macOS)
import Carbon.HIToolbox
import Foundation
import BudKit

/// The system-wide keys, registered through Carbon so they work inside the sandbox without the
/// accessibility permission. One handler for the app, with each key known by the id it was given
/// at registration; a key the system keeps for itself or another app is refused, and the caller
/// hears so.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private static let signature: OSType = 0x4255_4431 // "BUD1"

    private var handler: EventHandlerRef?
    private var keys: [UInt32: (ref: EventHotKeyRef, action: () -> Void)] = [:]
    private var next: UInt32 = 1

    /// The Carbon mask for the table's modifiers.
    static func carbon(_ modifiers: Key.Modifiers) -> UInt32 {
        var mask = 0
        if modifiers.contains(.control) { mask |= controlKey }
        if modifiers.contains(.option) { mask |= optionKey }
        if modifiers.contains(.shift) { mask |= shiftKey }
        if modifiers.contains(.command) { mask |= cmdKey }
        return UInt32(mask)
    }

    /// Registers a key by its place on the keyboard and gives back the id it answers under, nil
    /// when the system refuses the key.
    func register(_ key: PhysicalKey, action: @escaping () -> Void) -> UInt32? {
        install()
        let id = next
        next += 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(key.code), Self.carbon(key.modifiers), EventHotKeyID(signature: Self.signature, id: id), GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return nil }
        keys[id] = (ref, action)
        return id
    }

    func unregister(_ id: UInt32) {
        guard let entry = keys.removeValue(forKey: id) else { return }
        UnregisterEventHotKey(entry.ref)
    }

    fileprivate func fire(_ id: UInt32) {
        keys[id]?.action()
    }

    private func install() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var pressed = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            guard status == noErr else { return OSStatus(eventNotHandledErr) }
            let id = pressed.id
            Task { @MainActor in HotKeyCenter.shared.fire(id) }
            return noErr
        }, 1, &spec, nil, &handler)
    }
}

extension KeyboardLayout {
    /// The input source selected on the Mac, asked through Carbon for the character each key
    /// the keyboard has gives with nothing held, so the sheet shows a recorded key as this
    /// keyboard names it; the keypad and the keys of the JIS keyboard sit past the first fifty.
    static var mac: KeyboardLayout {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else { return .us }
        return withExtendedLifetime(source) { () -> KeyboardLayout in
            guard let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return .us }
            let data = unsafeBitCast(pointer, to: CFData.self)
            guard let bytes = CFDataGetBytePtr(data) else { return .us }
            let keyboard = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
            var table: [UInt16: Character] = [:]
            for code in UInt16(0)...127 {
                var deadKeys: UInt32 = 0
                var characters = [UniChar](repeating: 0, count: 4)
                var length = 0
                let status = UCKeyTranslate(keyboard, code, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, characters.count, &length, &characters)
                guard status == noErr, length > 0 else { continue }
                let text = String(utf16CodeUnits: characters, count: length)
                if let character = text.first, text.count == 1 { table[code] = character }
            }
            return KeyboardLayout(table)
        }
    }
}
#endif
