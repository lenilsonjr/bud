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
    /// Where lines go: the newest window's store. Every window of the app shows the same store.
    private var sink: ((Line) -> Void)?
    /// The windows listening. The sink stays until the last of them stops.
    private var listeners: Set<UUID> = []

    public init() {}

    public func send(_ line: Line) {
        if let sink { sink(line) } else { queue.append(line) }
    }

    /// Starts delivering for one more window, beginning with whatever waited. Keep the answer to
    /// stop that window alone.
    @discardableResult
    public func listen(_ sink: @escaping (Line) -> Void) -> UUID {
        let id = UUID()
        listeners.insert(id)
        self.sink = sink
        let waiting = queue
        queue = []
        waiting.forEach(sink)
        return id
    }

    /// Stops one window; while another listens, lines keep landing.
    public func stopListening(_ id: UUID) {
        listeners.remove(id)
        if listeners.isEmpty { sink = nil }
    }

    /// How many lines wait for a listener.
    public var waiting: Int { queue.count }
}
