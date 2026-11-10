import Foundation

/// A key the app answers to, named without SwiftUI so the table and its tests build anywhere.
public struct Key: Hashable, Sendable {
    /// The key itself, before any modifier: a letter, or one of the named keys the app uses.
    public enum Base: Hashable, Sendable {
        case letter(Character)
        case space, escape, `return`, tab, upArrow, downArrow
    }

    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
    }

    public let base: Base
    public let modifiers: Modifiers

    public init(_ base: Base, _ modifiers: Modifiers = []) {
        self.base = base
        self.modifiers = modifiers
    }

    public init(_ letter: Character, _ modifiers: Modifiers = []) {
        self.init(.letter(letter), modifiers)
    }

    /// Whether a modifier is part of the key. A bare key is a letter in a text field, so only a
    /// modified one can stand in a menu as its key equivalent.
    public var hasModifiers: Bool { !modifiers.isEmpty }

    /// The key the way the board draws it: ⌘K, ⇧⌘G, ⌥Space, Esc.
    public var label: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        switch base {
        case .letter(let letter): text += letter.uppercased()
        case .space: text += "Space"
        case .escape: text += "Esc"
        case .return: text += "↩"
        case .tab: text += "⇥"
        case .upArrow: text += "↑"
        case .downArrow: text += "↓"
        }
        return text
    }
}

/// One thing the app does on a key: a row of the one table every key is bound through. A later
/// sheet shows the table; a later recorder changes what each row answers to.
public struct Command: Hashable, Identifiable, Sendable {
    /// Where a command fires. Everywhere is the window; the canvas and Files are the two
    /// surfaces; a document is a bud's own page in Files.
    public enum Scope: String, CaseIterable, Sendable {
        case everywhere = "Everywhere", canvas = "Canvas", files = "Files", document = "Document"
    }

    public enum ID: String, CaseIterable, Sendable {
        case goAnywhere, capture, undo, canvas, files, newUnderThis
        case rowDown, rowUp, choose, openInFiles, close
        case open, back, nextMatch, previousMatch, soil, nest, rise
        case closeOrReopen, read, linkAsTyped
    }

    public let id: ID
    public let name: String
    public let scope: Scope
    /// The key the command answers to until the person records another.
    public let key: Key
    /// Whether the control that has the keyboard acts on the key itself, never the store: a
    /// list's rows, the bar's levels, the toast's Undo. Such a row is no menu item, since the
    /// menu runs commands through the store.
    public var inPlace = false

    /// Every command, in the order the menu lists them. Next row, Previous row, Choose and Close
    /// are the keys of whatever list has the keyboard: Go anywhere, the link picker, the tag and
    /// move pickers, the inline add bar.
    public static let all: [Command] = [
        Command(id: .goAnywhere, name: "Go anywhere", scope: .everywhere, key: Key("k", .command)),
        Command(id: .capture, name: "Capture", scope: .everywhere, key: Key(.space, .option)),
        Command(id: .undo, name: "Undo", scope: .everywhere, key: Key("z", .command), inPlace: true),
        Command(id: .canvas, name: "Canvas", scope: .everywhere, key: Key("1", .command)),
        Command(id: .files, name: "Files", scope: .everywhere, key: Key("2", .command)),
        Command(id: .newUnderThis, name: "New under this", scope: .everywhere, key: Key("n")),
        Command(id: .rowDown, name: "Next row", scope: .everywhere, key: Key(.downArrow), inPlace: true),
        Command(id: .rowUp, name: "Previous row", scope: .everywhere, key: Key(.upArrow), inPlace: true),
        Command(id: .choose, name: "Choose", scope: .everywhere, key: Key(.return), inPlace: true),
        Command(id: .openInFiles, name: "Open in Files", scope: .everywhere, key: Key(.return, .command), inPlace: true),
        Command(id: .close, name: "Close", scope: .everywhere, key: Key(.escape), inPlace: true),
        Command(id: .open, name: "Open", scope: .canvas, key: Key(.space)),
        Command(id: .back, name: "Back", scope: .canvas, key: Key(.escape)),
        Command(id: .nextMatch, name: "Next match", scope: .canvas, key: Key("g", .command)),
        Command(id: .previousMatch, name: "Previous match", scope: .canvas, key: Key("g", [.command, .shift])),
        Command(id: .soil, name: "Soil", scope: .canvas, key: Key("j", .command)),
        Command(id: .nest, name: "Add inside the last one", scope: .canvas, key: Key(.tab), inPlace: true),
        Command(id: .rise, name: "Back up a level", scope: .canvas, key: Key(.tab, .shift), inPlace: true),
        Command(id: .closeOrReopen, name: "Close or reopen", scope: .document, key: Key(.return, .command)),
        Command(id: .read, name: "Read", scope: .document, key: Key(.escape)),
        Command(id: .linkAsTyped, name: "Link as typed", scope: .document, key: Key(.tab), inPlace: true),
    ]

    private static let byID: [ID: Command] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    /// The row for an id. Every id has one: the table is checked against the cases in its tests.
    public static func of(_ id: ID) -> Command { byID[id]! }

    /// A scope's commands in the table's order, for the menu and the sheet.
    public static func all(in scope: Scope) -> [Command] {
        all.filter { $0.scope == scope }
    }

    /// The rows the Mac menu bar lists for a scope: the ones the store performs. A menu key
    /// equivalent is answered before any view sees the key, so a row that acts in place stays
    /// out, and no two menu rows may share a modified key whatever their scope.
    public static func menu(in scope: Scope) -> [Command] {
        all(in: scope).filter { !$0.inPlace }
    }

    /// The scopes with a menu row, in the table's order.
    public static var menuScopes: [Scope] {
        Scope.allCases.filter { !menu(in: $0).isEmpty }
    }
}
