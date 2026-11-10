import Foundation

/// The four ways of looking at the same tree, from the one center: the switch in the bar lists
/// them in this order. All four are built.
public enum Surface: String, CaseIterable, Sendable {
    case canvas = "Canvas"
    case files = "Files"
    case board = "Board"
    case calendar = "Calendar"

    /// The command that switches to the view: ⌘1 to ⌘4 in the table's order.
    public var command: Command.ID {
        switch self {
        case .canvas: return .canvas
        case .files: return .files
        case .board: return .board
        case .calendar: return .calendar
        }
    }
}

extension Command.ID {
    /// The view a command switches to, read from the one mapping above; nil for every other row.
    public var surface: Surface? { Surface.allCases.first { $0.command == self } }
}
