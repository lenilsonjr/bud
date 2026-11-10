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
    /// For the iPad: on the Mac the press carries what Option made of the key, so the recorder
    /// reads the event itself there.
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
            guard let typed = Base(typed: press.key.character) else { return nil }
            base = typed
        }
        self.init(base, Modifiers(press.modifiers))
    }

    #if os(macOS)
    /// The key a Mac key event is, by its code or its characters with the modifiers ignored.
    public init?(_ event: NSEvent) {
        self.init(characters: event.charactersIgnoringModifiers ?? "", keyCode: event.keyCode, modifiers: Modifiers(event.modifierFlags))
    }
    #endif
}

extension Key.Modifiers {
    /// The modifiers of a press, the four the table names.
    public init(_ modifiers: EventModifiers) {
        var out: Key.Modifiers = []
        if modifiers.contains(.control) { out.insert(.control) }
        if modifiers.contains(.option) { out.insert(.option) }
        if modifiers.contains(.shift) { out.insert(.shift) }
        if modifiers.contains(.command) { out.insert(.command) }
        self = out
    }

    #if os(macOS)
    /// The modifiers on a Mac key event, the four the table names.
    public init(_ flags: NSEvent.ModifierFlags) {
        var out: Key.Modifiers = []
        if flags.contains(.control) { out.insert(.control) }
        if flags.contains(.option) { out.insert(.option) }
        if flags.contains(.shift) { out.insert(.shift) }
        if flags.contains(.command) { out.insert(.command) }
        self = out
    }
    #endif
}

extension KeyLayout {
    /// A command's key for a button: `.keyboardShortcut(keys.shortcut(.goAnywhere))`.
    public func shortcut(_ id: Command.ID) -> KeyboardShortcut { key(for: id).shortcut }
    public func equivalent(_ id: Command.ID) -> KeyEquivalent { key(for: id).equivalent }
    public func modifiers(_ id: Command.ID) -> EventModifiers { key(for: id).eventModifiers }
}

/// The layout the window's views read their keys from, set once by the root view from its
/// store: the app's layout, or a picture's own. A view in no window reads the app's.
struct KeysKey: EnvironmentKey {
    static let defaultValue = Keys.layout
}

extension EnvironmentValues {
    var keys: KeyLayout {
        get { self[KeysKey.self] }
        set { self[KeysKey.self] = newValue }
    }
}

extension Keys {
    /// The app's key for a button where no window's layout is at hand.
    public static func shortcut(_ id: Command.ID) -> KeyboardShortcut { layout.shortcut(id) }
    public static func equivalent(_ id: Command.ID) -> KeyEquivalent { layout.equivalent(id) }
    public static func modifiers(_ id: Command.ID) -> EventModifiers { layout.modifiers(id) }

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
    /// The key is the window's layout's, read from the environment.
    public func onKey(_ id: Command.ID, phases: KeyPress.Phases = [.down, .repeat], action: @escaping (KeyPress) -> KeyPress.Result) -> some View {
        modifier(OnKey(id: id, phases: phases, action: action))
    }
}

/// `onKey` as a modifier, so the key it listens for comes from the layout in the environment.
private struct OnKey: ViewModifier {
    let id: Command.ID
    let phases: KeyPress.Phases
    let action: (KeyPress) -> KeyPress.Result
    @Environment(\.keys) private var keys

    func body(content: Content) -> some View {
        let key = keys.key(for: id)
        return content.onKeyPress(keys: [key.equivalent], phases: phases) { press in
            guard press.modifiers.isSuperset(of: key.eventModifiers) else { return .ignored }
            return action(press)
        }
    }
}
#endif
