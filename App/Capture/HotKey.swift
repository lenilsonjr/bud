#if os(macOS)
import Carbon.HIToolbox
import Foundation
import BudKit

/// A system-wide key, registered through Carbon so it works inside the sandbox without the
/// accessibility permission. One handler for the app; the key is unregistered on stop.
final class HotKey {
    /// A key from the table the way Carbon names it: a code and a modifier mask. Nil for a
    /// letter, whose code depends on the keyboard layout; the recorder will map those.
    static func carbon(_ key: Key) -> (code: UInt32, modifiers: UInt32)? {
        let code: Int
        switch key.base {
        case .letter: return nil
        case .space: code = kVK_Space
        case .escape: code = kVK_Escape
        case .return: code = kVK_Return
        case .tab: code = kVK_Tab
        case .upArrow: code = kVK_UpArrow
        case .downArrow: code = kVK_DownArrow
        }
        var modifiers = 0
        if key.modifiers.contains(.control) { modifiers |= controlKey }
        if key.modifiers.contains(.option) { modifiers |= optionKey }
        if key.modifiers.contains(.shift) { modifiers |= shiftKey }
        if key.modifiers.contains(.command) { modifiers |= cmdKey }
        return (UInt32(code), UInt32(modifiers))
    }

    private let keyCode: UInt32
    private let modifiers: UInt32
    private let action: @MainActor () -> Void
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping @MainActor () -> Void) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.action = action
    }

    func register() {
        guard hotKey == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let key = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            Task { @MainActor in key.action() }
            return noErr
        }, 1, &spec, me, &handler)
        let id = EventHotKeyID(signature: 0x4255_4431, id: 1) // "BUD1"
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKey)
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
    }

    deinit { unregister() }
}
#endif
