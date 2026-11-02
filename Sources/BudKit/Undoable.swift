import Foundation

/// One thing that can be taken back: what the toast says, and how to undo it.
public struct Undoable: Sendable {
    public let message: String
    public let undo: @Sendable () -> Void
    /// Whether the toast shows Undo; a toast that only reports something has nothing to take back.
    public let offersUndo: Bool

    public init(message: String, offersUndo: Bool = true, undo: @escaping @Sendable () -> Void) {
        self.message = message
        self.offersUndo = offersUndo
        self.undo = undo
    }

    /// A toast that only says something.
    public static func notice(_ message: String) -> Undoable {
        Undoable(message: message, offersUndo: false) {}
    }
}
