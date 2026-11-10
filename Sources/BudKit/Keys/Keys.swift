import Foundation

/// The key each command answers to. Today the default from the table; the layer the person
/// records comes later, so every binding reads through here and nowhere else.
public enum Keys {
    public static func key(for id: Command.ID) -> Key { Command.of(id).key }
}
