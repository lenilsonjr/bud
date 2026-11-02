import Foundation

/// One thing the toast reports: what it says, an optional mark before it, and how to take it
/// back when it can be taken back.
public struct Undoable: Sendable {
    public let message: String
    /// The SF Symbol before the message, when the toast carries one.
    public let systemImage: String?
    /// Nil for a toast that only reports: the Undo button stays away.
    public let undo: (@Sendable () -> Void)?

    public init(message: String, systemImage: String? = nil, undo: (@Sendable () -> Void)? = nil) {
        self.message = message
        self.systemImage = systemImage
        self.undo = undo
    }
}
