import Foundation

/// The key each command answers to, read through the layout on this device and nowhere else: a
/// key recorded over the table's default, else the default.
public enum Keys {
    public static let layout = KeyLayout()

    public static func key(for id: Command.ID) -> Key { layout.key(for: id) }
}
