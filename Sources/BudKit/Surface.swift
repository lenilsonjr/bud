import Foundation

/// The four ways of looking at the same tree, from the one center: the switch in the bar lists
/// them in this order. The canvas and Files are built; Board and Calendar show a quiet page with
/// their name until they are.
public enum Surface: String, CaseIterable, Sendable {
    case canvas = "Canvas"
    case files = "Files"
    case board = "Board"
    case calendar = "Calendar"

    /// The one line under the name on a quiet page: "The board view is coming."
    public var comingLine: String { "The \(rawValue.lowercased()) view is coming." }
}
