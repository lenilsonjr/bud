import Foundation

/// The words and the grouping of the keyboard shortcuts sheet, kept pure so they test on their own.
public enum ShortcutText {
    public static let title = "Keyboard shortcuts"

    /// The line under the title.
    public static let note = "Click a key to record a new one."

    /// The keycap of a row while it records, and the line under it.
    public static let recording = "Press keys…"
    public static let recordingHint = "Esc cancels."
    /// The line under a row that fires everywhere once a bare key was pressed for it.
    public static let bareKeyRefused = "Hold ⌘, ⌥ or ⌃ with it: alone it would type."
    /// The line under a row for a beat after a key the table has no name for.
    public static let unnamedKey = "That key cannot be recorded."

    /// The line under the row that wants a key another holds, and the one under the holder.
    public static func taken(by holder: Command, key: Key) -> String {
        "\(holder.name) already answers to \(key.label)."
    }

    public static func wanted(by wanter: Command) -> String {
        "\(wanter.name) wants this key."
    }

    /// The row's way back to its default, and the sheet's for every row at once.
    public static let reset = "Reset"
    public static let resetAll = "Reset all"

    /// The footer's count of recorded keys; nothing while every row has its default.
    public static func changed(_ count: Int) -> String? {
        guard count > 0 else { return nil }
        return "\(count) \(count == 1 ? "key" : "keys") changed from the defaults"
    }

    /// The group of the keys the Mac answers to from the desktop, and the line under its title.
    public static let systemWideTitle = "From any app"
    public static let systemWideCaption = "On the Mac, with any app in front, whatever the input source."
    /// The line under a row of that group whose key the system would not give the app.
    public static let takenBySystem = "Another app or the system already answers to this key."

    /// A scope's title in the sheet.
    public static func groupTitle(_ scope: Command.Scope) -> String {
        switch scope {
        case .everywhere: return "Everywhere"
        case .canvas: return "On the canvas"
        case .files: return "In Files"
        case .document: return "On a page"
        }
    }

    /// One group of rows: a title, a caption under it when the group needs one, and the commands.
    public struct Group: Equatable, Sendable {
        public var title: String
        public var caption: String?
        public var commands: [Command]

        /// The lines the group takes on the sheet, the title counted, so two columns can share them.
        var height: Int { commands.count + 1 + (caption == nil ? 0 : 1) }
    }

    /// The groups in the sheet's order: each scope with its rows from the table, the system-wide
    /// ones left out, then those last in their own group marked Mac; a scope with no rows is not
    /// shown.
    public static func groups() -> [Group] {
        var groups: [Group] = []
        for scope in Command.Scope.allCases {
            let commands = Command.all(in: scope).filter { !Command.systemWide.contains($0.id) }
            if !commands.isEmpty { groups.append(Group(title: groupTitle(scope), caption: nil, commands: commands)) }
        }
        let systemWide = Command.systemWide.map(Command.of)
        if !systemWide.isEmpty { groups.append(Group(title: systemWideTitle, caption: systemWideCaption, commands: systemWide)) }
        return groups
    }

    /// The groups over two columns, whole: the left takes groups in order while that brings it
    /// nearer to half the lines, the right takes the rest.
    public static func halves(_ groups: [Group]) -> ([Group], [Group]) {
        let half = Double(groups.map(\.height).reduce(0, +)) / 2
        var left: [Group] = []
        var lines = 0
        for group in groups {
            if abs(Double(lines + group.height) - half) > abs(Double(lines) - half) { break }
            left.append(group)
            lines += group.height
        }
        return (left, Array(groups.dropFirst(left.count)))
    }
}
