import Foundation

/// The bridge from a capture made outside the window (the ⌥Space panel) to the store inside it.
/// Lines sent before a window listens wait in order and land when one does.
@MainActor
public final class CaptureRelay {
    public static let shared = CaptureRelay()

    /// One captured line: the text, whether it is a to-do, the app it was captured over, and
    /// the device word the Inbox shows.
    public struct Line: Equatable, Sendable {
        public let text: String
        public let todo: Bool
        public let from: String?
        public let source: String

        public init(text: String, todo: Bool = false, from: String? = nil, source: String = "desktop") {
            self.text = text
            self.todo = todo
            self.from = from
            self.source = source
        }

        /// The body a capture carries: where it came from, when that is known.
        public var body: String { from.map { "from \($0)" } ?? "" }
    }

    private var queue: [Line] = []
    /// The windows listening, newest last. A line goes to the newest one only, so it lands once.
    private var sinks: [(id: UUID, sink: (Line) -> Void)] = []

    public init() {}

    public func send(_ line: Line) {
        if let sink = sinks.last?.sink { sink(line) } else { queue.append(line) }
    }

    /// Starts delivering to one more window, beginning with whatever waited. Keep the answer to
    /// stop that window alone.
    @discardableResult
    public func listen(_ sink: @escaping (Line) -> Void) -> UUID {
        let id = UUID()
        sinks.append((id, sink))
        let waiting = queue
        queue = []
        waiting.forEach(sink)
        return id
    }

    /// Stops one window; the others keep listening.
    public func stopListening(_ id: UUID) { sinks.removeAll { $0.id == id } }

    /// How many lines wait for a listener.
    public var waiting: Int { queue.count }
}
