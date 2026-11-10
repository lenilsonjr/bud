import Foundation

/// The words and the grouping of the keyboard shortcuts sheet, kept pure so they test on their own.
public enum ShortcutText {
    public static let title = "Keyboard shortcuts"

    /// The line under the title.
    public static let note = "Every key the app answers to."

    /// The group of the keys the Mac answers to from the desktop, and the line under its title.
    public static let systemWideTitle = "From any app"
    public static let systemWideCaption = "On the Mac, with any app in front."

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

    /// The groups in the sheet's order: the system-wide keys first, then each scope with its rows
    /// from the table, the system-wide ones left out; a scope with no rows is not shown.
    public static func groups() -> [Group] {
        let systemWide = Command.systemWide.map(Command.of)
        var groups = [Group(title: systemWideTitle, caption: systemWideCaption, commands: systemWide)]
        for scope in Command.Scope.allCases {
            let commands = Command.all(in: scope).filter { !Command.systemWide.contains($0.id) }
            if !commands.isEmpty { groups.append(Group(title: groupTitle(scope), caption: nil, commands: commands)) }
        }
        return groups
    }

    /// The groups over two columns, whole: the left takes groups in order until it holds half the
    /// lines, the right takes the rest.
    public static func halves(_ groups: [Group]) -> ([Group], [Group]) {
        let half = Double(groups.map(\.height).reduce(0, +)) / 2
        var left: [Group] = []
        var lines = 0
        for group in groups {
            if Double(lines) >= half { break }
            left.append(group)
            lines += group.height
        }
        return (left, Array(groups.dropFirst(left.count)))
    }
}
