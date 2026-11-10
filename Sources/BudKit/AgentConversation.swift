import Foundation

/// The chat in the Agent panel: the person's bubbles and the agent's, the changes the agent
/// made between them, whether the agent is typing, and whether the page goes along with what
/// is sent. Nothing here talks to an agent; the panel reads and changes this, and the thing
/// that runs one fills it in.
public struct AgentConversation: Equatable, Sendable {
    /// Who said a bubble: the person on the right, the agent on the left.
    public enum Who: String, Equatable, Sendable {
        case person, agent
    }

    /// One bubble. `read` is the agent's mark that it saw the person's; the panel writes "Read"
    /// under the last one so marked.
    public struct Message: Identifiable, Equatable, Sendable {
        public var id: UUID
        public var who: Who
        public var text: String
        public var read: Bool

        public init(id: UUID = UUID(), who: Who, text: String, read: Bool = false) {
            self.id = id
            self.who = who
            self.text = text
            self.read = read
        }
    }

    /// A change the agent made, as one line between bubbles with Undo beside it until it is
    /// taken back.
    public struct Change: Identifiable, Equatable, Sendable {
        public var id: UUID
        public var summary: String
        public var undone: Bool

        public init(id: UUID = UUID(), summary: String, undone: Bool = false) {
            self.id = id
            self.summary = summary
            self.undone = undone
        }
    }

    /// The thread, top to bottom.
    public enum Entry: Identifiable, Equatable, Sendable {
        case message(Message)
        case change(Change)

        public var id: UUID {
            switch self {
            case .message(let message): return message.id
            case .change(let change): return change.id
            }
        }
    }

    public var entries: [Entry]
    /// Whether the agent is writing back: the three dots at the end of the thread.
    public var typing: Bool
    /// Whether the page goes with the next message: the This page chip in the composer, on until
    /// its × takes it off and off until its + brings it back.
    public var includesPage: Bool
    /// What is typed in the composer and not sent yet. Kept here so the panel can move between
    /// the sidebars without losing it.
    public var draft: String

    public init(entries: [Entry] = [], typing: Bool = false, includesPage: Bool = true, draft: String = "") {
        self.entries = entries
        self.typing = typing
        self.includesPage = includesPage
        self.draft = draft
    }

    public var messages: [Message] {
        entries.compactMap { if case .message(let message) = $0 { return message } else { return nil } }
    }

    /// The person's last bubble the agent has read, where "Read" goes; none once a later one of
    /// theirs is waiting.
    public var lastRead: Message.ID? {
        guard let last = messages.last(where: { $0.who == .person }), last.read else { return nil }
        return last.id
    }

    /// Takes a change back; the line then says so instead of offering Undo.
    public mutating func undo(_ id: Change.ID) {
        entries = entries.map { entry in
            guard case .change(var change) = entry, change.id == id else { return entry }
            change.undone = true
            return .change(change)
        }
    }

    /// The page the chip stands for: what the agent gets to read along with the message.
    public struct Page: Equatable, Sendable {
        public var title: String
        public var body: String

        public init(title: String, body: String) {
            self.title = title
            self.body = body
        }
    }

    /// What goes to the agent for one message: the person's words, and the page when the chip
    /// is on.
    public struct Request: Equatable, Sendable {
        public var text: String
        public var page: Page?

        public init(text: String, page: Page? = nil) {
            self.text = text
            self.page = page
        }

        /// The prompt as the agent reads it: the page first, named and quoted, then the words.
        public var prompt: String {
            guard let page else { return text }
            var lines = ["The page \"\(page.title)\":"]
            let body = page.body.trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty { lines.append(body) }
            lines.append(text)
            return lines.joined(separator: "\n\n")
        }
    }

    /// The request a message makes from here: with the page while the chip is on and there is
    /// a page to send.
    public func request(for text: String, page: Page?) -> Request {
        Request(text: text, page: includesPage ? page : nil)
    }

    /// The prompt for a message, as `request(for:page:)` composes it.
    public func prompt(for text: String, page: Page?) -> String {
        request(for: text, page: page).prompt
    }

    /// Sends a message: the person's bubble joins the thread and, until an agent runs, a quiet
    /// line from the agent's side says there is none. Nothing is sent for an empty message.
    @discardableResult
    public mutating func send(_ text: String, page: Page?) -> Request? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        entries.append(.message(Message(who: .person, text: text)))
        entries.append(.message(Message(who: .agent, text: AgentText.noAgent)))
        return request(for: text, page: page)
    }

    /// Sends what is typed and clears it; the words stay when nothing was sent.
    @discardableResult
    public mutating func sendDraft(page: Page?) -> Request? {
        guard let request = send(draft, page: page) else { return nil }
        draft = ""
        return request
    }

    /// A conversation about a page, for the pictures and the tests: a question answered, a
    /// change made, the person's last bubble read, the agent typing.
    public static func scripted(on page: String) -> AgentConversation {
        AgentConversation(entries: [
            .message(Message(who: .person, text: "can you make a checklist from this page?", read: true)),
            .message(Message(who: .agent, text: "on it")),
            .message(Message(who: .agent, text: "found 5 things: ask two readers, check the domain, draft the first issue, pick a typeface and book the printer")),
            .change(Change(summary: "Added 5 buds to \(page)")),
            .message(Message(who: .person, text: "which one first?", read: true)),
            .message(Message(who: .agent, text: "the readers, the rest waits on the name. want me to put a day on it?")),
            .message(Message(who: .person, text: "yes pls", read: true)),
        ], typing: true)
    }
}

/// The Agent panel's words, here so a test reads them on any platform.
public enum AgentText {
    /// The agent's line under a message sent before an agent is set up.
    public static let noAgent = "No agent is set up yet."
    /// The composer's field while empty.
    public static let placeholder = "Text the agent"
    /// The chip that sends the page along.
    public static let thisPage = "This page"
    /// Under the person's last bubble the agent has read.
    public static let read = "Read"
    public static let undo = "Undo"
    /// In place of Undo once a change is taken back.
    public static let undone = "Undone"
    public static let send = "Send"
    public static let removePage = "Send without this page"
    public static let addPage = "Send this page along"
    /// The thread before anything is said.
    public static let empty = "Nothing said yet."
    /// The picker's two headings.
    public static let app = "App"
    public static let model = "Model"
    /// Under an app's name in the picker.
    public static let signedIn = "Installed · signed in"
    public static let notSignedIn = "Installed · not signed in"
    public static let notInstalled = "Not installed"
    /// Under the picker while the chosen app is installed and signed in.
    public static let runsHere = "Runs on this Mac with your own account"
    /// The button that opens the picker.
    public static let pick = "Pick the app and the model"
}
