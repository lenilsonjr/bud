import Foundation

/// One thing that can be taken back: what the toast says, and how to undo it.
public struct Undoable: Sendable {
    public let message: String
    public let undo: @Sendable () -> Void

    public init(message: String, undo: @escaping @Sendable () -> Void) {
        self.message = message
        self.undo = undo
    }
}
