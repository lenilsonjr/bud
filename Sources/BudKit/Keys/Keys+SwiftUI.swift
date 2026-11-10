#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// The table's keys the way SwiftUI binds them. The only place a key becomes a `KeyEquivalent`
/// or a `KeyboardShortcut`: a view asks for a command, never for a letter.
extension Key {
    public var equivalent: KeyEquivalent {
        switch base {
        case .letter(let letter): return KeyEquivalent(letter)
        case .space: return .space
        case .escape: return .escape
        case .return: return .return
        case .tab: return .tab
        case .upArrow: return .upArrow
        case .downArrow: return .downArrow
        }
    }

    public var eventModifiers: EventModifiers {
        var out: EventModifiers = []
        if modifiers.contains(.control) { out.insert(.control) }
        if modifiers.contains(.option) { out.insert(.option) }
        if modifiers.contains(.shift) { out.insert(.shift) }
        if modifiers.contains(.command) { out.insert(.command) }
        return out
    }

    public var shortcut: KeyboardShortcut { KeyboardShortcut(equivalent, modifiers: eventModifiers) }

    /// The key a press is, with the modifiers held, when the table can name it: a letter, a
    /// number or a sign, or one of the named keys. Nil for the rest, a function key or Delete.
    public init?(_ press: KeyPress) {
        let base: Base
        switch press.key {
        case .space: base = .space
        case .escape: base = .escape
        case .return: base = .return
        case .tab: base = .tab
        case .upArrow: base = .upArrow
        case .downArrow: base = .downArrow
        default:
            let character = press.key.character
            guard character.isLetter || character.isNumber || character.isPunctuation || character.isSymbol else { return nil }
            base = .letter(character.lowercased().first ?? character)
        }
        var modifiers: Modifiers = []
        if press.modifiers.contains(.control) { modifiers.insert(.control) }
        if press.modifiers.contains(.option) { modifiers.insert(.option) }
        if press.modifiers.contains(.shift) { modifiers.insert(.shift) }
        if press.modifiers.contains(.command) { modifiers.insert(.command) }
        self.init(base, modifiers)
    }
}

extension Keys {
    /// A command's key for a button: `.keyboardShortcut(Keys.shortcut(.goAnywhere))`.
    public static func shortcut(_ id: Command.ID) -> KeyboardShortcut { key(for: id).shortcut }
    public static func equivalent(_ id: Command.ID) -> KeyEquivalent { key(for: id).equivalent }
    public static func modifiers(_ id: Command.ID) -> EventModifiers { key(for: id).eventModifiers }

    /// Whether a text field has the keyboard, so a bare key is a letter typed and not a command.
    @MainActor public static var typing: Bool {
        #if os(macOS)
        return NSApp.keyWindow?.firstResponder is NSTextView
        #else
        return UIResponder.first is UITextInput
        #endif
    }
}

#if !os(macOS)
extension UIResponder {
    private static weak var noted: UIResponder?

    @objc private func noteFirstResponder() { UIResponder.noted = self }

    /// The first responder, asked for in one step: an action sent to nil lands on it.
    @MainActor static var first: UIResponder? {
        noted = nil
        UIApplication.shared.sendAction(#selector(noteFirstResponder), to: nil, from: nil, for: nil)
        return noted
    }
}
#endif

extension View {
    /// Runs `action` on a command's key while this view or one inside it has focus; the key's
    /// modifiers must all be down. The result says whether the key goes on to the next view.
    public func onKey(_ id: Command.ID, phases: KeyPress.Phases = [.down, .repeat], action: @escaping (KeyPress) -> KeyPress.Result) -> some View {
        let key = Keys.key(for: id)
        return onKeyPress(keys: [key.equivalent], phases: phases) { press in
            guard press.modifiers.isSuperset(of: key.eventModifiers) else { return .ignored }
            return action(press)
        }
    }
}
#endif
