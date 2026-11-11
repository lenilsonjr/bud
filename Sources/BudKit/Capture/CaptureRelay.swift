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
    /// The stores listening, newest last, each with the windows that show it. A line goes to the
    /// newest store that still has a window open, so it lands once.
    private var stores: [(store: ObjectIdentifier, windows: Set<UUID>, sink: (Line) -> Void)] = []

    public init() {}

    public func send(_ line: Line) {
        if let sink = stores.last?.sink { sink(line) } else { queue.append(line) }
    }

    /// Starts delivering into `store` for one more window, beginning with whatever waited. Keep
    /// the answer to stop that window alone.
    @discardableResult
    public func listen(for store: AnyObject, _ sink: @escaping (Line) -> Void) -> UUID {
        let id = UUID()
        let key = ObjectIdentifier(store)
        var windows: Set<UUID> = [id]
        if let i = stores.firstIndex(where: { $0.store == key }) { windows.formUnion(stores.remove(at: i).windows) }
        stores.append((key, windows, sink))
        let waiting = queue
        queue = []
        waiting.forEach(sink)
        return id
    }

    /// Stops one window. A store goes once its last window does; the others keep listening.
    public func stopListening(_ id: UUID) {
        for i in stores.indices { stores[i].windows.remove(id) }
        stores.removeAll { $0.windows.isEmpty }
    }

    /// How many lines wait for a listener.
    public var waiting: Int { queue.count }
}
