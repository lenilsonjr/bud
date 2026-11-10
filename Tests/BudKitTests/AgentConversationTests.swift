import XCTest
@testable import BudKit

final class AgentConversationTests: XCTestCase {
    private let page = AgentConversation.Page(title: "Pick a name", body: "Short, warm, and easy to say out loud.")

    func testTheScriptReadsAsThePictureShowsIt() {
        let chat = AgentConversation.scripted(on: "Pick a name")
        XCTAssertEqual(chat.messages.map(\.who), [.person, .agent, .agent, .person, .agent, .person])
        XCTAssertEqual(chat.messages.first?.text, "can you make a checklist from this page?")
        XCTAssertTrue(chat.typing)
        XCTAssertTrue(chat.includesPage)
        XCTAssertEqual(chat.lastRead, chat.messages.last?.id, "Read goes under the person's last bubble")
        let changes = chat.entries.compactMap { if case .change(let change) = $0 { return change } else { return nil } }
        XCTAssertEqual(changes.map(\.summary), ["Added 5 buds to Pick a name"])
        XCTAssertEqual(changes.map(\.undone), [false])
        XCTAssertEqual(chat.entries.map(\.id).count, Set(chat.entries.map(\.id)).count, "Every entry has its own id")
    }

    func testReadGoesUnderThePersonsLastBubbleOnlyWhileTheAgentHasSeenIt() {
        var chat = AgentConversation()
        XCTAssertNil(chat.lastRead)
        let first = AgentConversation.Message(who: .person, text: "hello", read: true)
        chat.entries = [.message(first), .message(AgentConversation.Message(who: .agent, text: "hi"))]
        XCTAssertEqual(chat.lastRead, first.id)
        let waiting = AgentConversation.Message(who: .person, text: "are you there?")
        chat.entries.append(.message(waiting))
        XCTAssertNil(chat.lastRead, "A later bubble of theirs is still waiting")
        chat.entries = [.message(AgentConversation.Message(who: .agent, text: "hi", read: true))]
        XCTAssertNil(chat.lastRead, "The agent's bubbles carry no Read")
    }

    func testUndoTakesAChangeBackAndTheLineSaysSo() {
        var chat = AgentConversation.scripted(on: "Pick a name")
        let change = chat.entries.compactMap { if case .change(let change) = $0 { return change } else { return nil } }[0]
        chat.undo(change.id)
        guard case .change(let after)? = chat.entries.first(where: { $0.id == change.id }) else { return XCTFail("The change stays in the thread") }
        XCTAssertTrue(after.undone)
        XCTAssertEqual(after.summary, change.summary)
        XCTAssertEqual(chat.messages.map(\.text), AgentConversation.scripted(on: "Pick a name").messages.map(\.text), "The bubbles are untouched")
    }

    func testThePromptCarriesThePageWhileTheChipIsOn() {
        var chat = AgentConversation()
        XCTAssertEqual(
            chat.prompt(for: "what is this about?", page: page),
            "The page \"Pick a name\":\n\nShort, warm, and easy to say out loud.\n\nwhat is this about?"
        )
        XCTAssertEqual(chat.request(for: "what is this about?", page: page), AgentConversation.Request(text: "what is this about?", page: page))
        chat.includesPage = false
        XCTAssertEqual(chat.prompt(for: "what is this about?", page: page), "what is this about?", "Without the chip, the words alone")
        XCTAssertNil(chat.request(for: "what is this about?", page: page).page)
        chat.includesPage = true
        XCTAssertEqual(chat.prompt(for: "hello", page: nil), "hello", "A lens has no page to send")
        let bare = AgentConversation.Page(title: "Q4 roadmap", body: "  \n")
        XCTAssertEqual(chat.prompt(for: "plan it", page: bare), "The page \"Q4 roadmap\":\n\nplan it", "An empty body is left out")
    }

    func testSendAppendsThePersonsBubbleAndTheQuietLineUntilAnAgentRuns() {
        var chat = AgentConversation()
        let request = chat.send("  make a checklist  ", page: page)
        XCTAssertEqual(request, AgentConversation.Request(text: "make a checklist", page: page))
        XCTAssertEqual(chat.messages.map(\.who), [.person, .agent])
        XCTAssertEqual(chat.messages.map(\.text), ["make a checklist", AgentText.noAgent])
        XCTAssertEqual(chat.messages.map(\.read), [false, false])
        XCTAssertFalse(chat.typing)
        XCTAssertNil(chat.lastRead)
        XCTAssertNil(chat.send("   ", page: page), "An empty message sends nothing")
        XCTAssertEqual(chat.messages.count, 2)
        chat.includesPage = false
        XCTAssertEqual(chat.send("again", page: page)?.page, nil)
    }

    func testTheWordsReadAsTheDesignWritesThem() {
        XCTAssertEqual(AgentText.noAgent, "No agent is set up yet.")
        XCTAssertEqual(AgentText.thisPage, "This page")
        XCTAssertEqual(AgentText.read, "Read")
        XCTAssertEqual(AgentText.undo, "Undo")
        XCTAssertEqual(AgentText.undone, "Undone")
        XCTAssertEqual(AgentText.send, "Send")
        XCTAssertEqual(AgentText.placeholder, "Text the agent")
        XCTAssertEqual(AgentText.empty, "Nothing said yet.")
        XCTAssertEqual(PagePanel.agent.title, "Agent")
    }
}
