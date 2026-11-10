import Foundation

/// A key by its place on the keyboard: the code the hardware sends for it and the modifiers
/// held. The keys the Mac answers to from the desktop are recorded and registered this way, so
/// the key under the finger stays the same whatever the input source; the sheet shows the
/// character the layout in use gives the code.
public struct PhysicalKey: Hashable, Codable, Sendable {
    public let code: UInt16
    public let modifiers: Key.Modifiers

    public init(code: UInt16, modifiers: Key.Modifiers) {
        self.code = code
        self.modifiers = modifiers
    }

    /// Where a key of the table sits on the US keyboard, nil for a letter the US layout has no
    /// key for. The table's defaults are named, so a default system-wide key is registered from
    /// this before anything is recorded.
    public init?(_ key: Key) {
        guard let code = KeyboardLayout.code(for: key.base) else { return nil }
        self.init(code: code, modifiers: key.modifiers)
    }

    /// The key as a layout names it: the named keys by their code, the rest by the character the
    /// layout gives the code, the US layout standing in for a code the layout gives nothing the
    /// table can name. Nil for a code no layout names: a function key, Delete.
    public func key(in layout: KeyboardLayout = .current) -> Key? {
        guard let base = layout.base(for: code) ?? KeyboardLayout.us.base(for: code) else { return nil }
        return Key(base, modifiers)
    }

    private enum CodingKeys: String, CodingKey {
        case code, modifiers
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(code: try container.decode(UInt16.self, forKey: .code), modifiers: Key.Modifiers(rawValue: try container.decode(UInt8.self, forKey: .modifiers)))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(code, forKey: .code)
        try container.encode(modifiers.rawValue, forKey: .modifiers)
    }
}

/// The characters a keyboard layout gives the physical keys, by the codes the hardware sends.
/// The named keys sit at the same codes on every layout; the letters, numbers and signs move
/// with the input source.
public struct KeyboardLayout: Sendable {
    /// The character a code gives with nothing held, nil for a code the layout gives none.
    public let characters: @Sendable (UInt16) -> Character?

    public init(characters: @escaping @Sendable (UInt16) -> Character?) {
        self.characters = characters
    }

    public init(_ table: [UInt16: Character]) {
        self.init { table[$0] }
    }

    /// The layout in use: the US one until the app sets the input source selected on the Mac,
    /// and again whenever that changes.
    public static var current: KeyboardLayout = .us

    /// The named keys of the table, at the codes every layout keeps for them.
    public static let named: [UInt16: Key.Base] = [
        49: .space, 53: .escape, 36: .return, 76: .return, 48: .tab, 126: .upArrow, 125: .downArrow,
    ]

    /// The US layout: the letters, numbers and signs by the codes of the ANSI keyboard, with the
    /// section key of the ISO one.
    public static let us = KeyboardLayout(usTable)

    /// What this layout makes of a code: a named key by its code, else the character the layout
    /// gives it when the table can name that, nil otherwise.
    public func base(for code: UInt16) -> Key.Base? {
        if let named = Self.named[code] { return named }
        guard let character = characters(code),
              character.isLetter || character.isNumber || character.isPunctuation || character.isSymbol
        else { return nil }
        return .letter(character.lowercased().first ?? character)
    }

    /// The code of a key of the table on the US keyboard: the named keys by their own code, a
    /// letter by the key that types it there. Nil for a letter no US key types.
    public static func code(for base: Key.Base) -> UInt16? {
        if let code = named.first(where: { $0.value == base })?.key {
            return base == .return ? 36 : code
        }
        guard case .letter(let letter) = base else { return nil }
        return usCodes[letter]
    }

    private static let usCodes: [Character: UInt16] = Dictionary(uniqueKeysWithValues: usTable.map { ($0.value, $0.key) })

    private static let usTable: [UInt16: Character] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v", 10: "§",
        11: "b", 12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t", 18: "1", 19: "2", 20: "3",
        21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]",
        31: "o", 32: "u", 33: "[", 34: "i", 35: "p", 37: "l", 38: "j", 39: "'", 40: "k", 41: ";",
        42: "\\", 43: ",", 44: "/", 45: "n", 46: "m", 47: ".", 50: "`",
    ]
}
