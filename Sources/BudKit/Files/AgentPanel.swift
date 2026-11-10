#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// The chat with the agent as a panel: the thread growing up from the bottom, the person's
/// bubbles green on the right and the agent's grey on the left, a change the agent made as one
/// line between them, "Read" under the last bubble it saw, three dots while it writes; the
/// composer under it all. Like Files, it takes the rest of its sidebar.
struct AgentPanel: View {
    @ObservedObject var store: BudStore

    var body: some View {
        PanelView(panel: .agent, store: store) {
            VStack(spacing: 0) {
                AgentThread(conversation: store.agent) { store.agent.undo($0) }
                AgentComposer(store: store)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxHeight: store.panels.isCollapsed(.agent) ? nil : .infinity, alignment: .top)
    }
}

/// The one-off sizes of the chat: a bubble's text a step under the body, the small marks under
/// and between the bubbles.
enum AgentPanelText {
    static let bubble = PanelText.title
    static let mark = TextStyle(typeface: .text, size: 10, weight: 600)
    static let chip = TextStyle(typeface: .text, size: 11, weight: 600)
}

/// The bubbles, bottom-aligned and scrolling when there are more than fit.
struct AgentThread: View {
    let conversation: AgentConversation
    let onUndo: (AgentConversation.Change.ID) -> Void

    var body: some View {
        MaybeScroll {
            VStack(alignment: .leading, spacing: 3) {
                Spacer(minLength: 0)
                if conversation.entries.isEmpty && !conversation.typing {
                    Text(AgentText.empty)
                        .textRole(.caption)
                        .foregroundStyle(Theme.text3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 2)
                }
                ForEach(conversation.entries) { entry in
                    switch entry {
                    case .message(let message):
                        AgentBubble(message: message)
                        if message.id == conversation.lastRead {
                            Text(AgentText.read)
                                .textStyle(AgentPanelText.mark)
                                .foregroundStyle(Theme.text3)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .padding(.horizontal, 4)
                                .accessibilityIdentifier("agent-read")
                        }
                    case .change(let change):
                        AgentChangeLine(change: change) { onUndo(change.id) }
                    }
                }
                if conversation.typing { AgentTypingBubble() }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .bottom)
        }
        .defaultScrollAnchor(.bottom)
        .accessibilityIdentifier("agent-thread")
    }
}

/// One bubble: the person's in leaf on the right with its tail at the bottom right, the agent's
/// raised on the left with its tail at the bottom left.
struct AgentBubble: View {
    let message: AgentConversation.Message

    private var mine: Bool { message.who == .person }

    var body: some View {
        Text(message.text)
            .textStyle(AgentPanelText.bubble)
            .lineSpacing(13 * 0.35)
            .foregroundStyle(mine ? Theme.onLeaf : Theme.text)
            .multilineTextAlignment(.leading)
            .padding(.vertical, 7)
            .padding(.horizontal, 12)
            .background(mine ? Theme.leafFill : Theme.raised, in: shape)
            .overlay { if !mine { shape.stroke(Theme.line, lineWidth: 1) } }
            .frame(maxWidth: 230, alignment: mine ? .trailing : .leading)
            .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
            .accessibilityLabel("\(mine ? "You" : "Agent"): \(message.text)")
    }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 17, bottomLeadingRadius: mine ? 17 : 4,
            bottomTrailingRadius: mine ? 4 : 17, topTrailingRadius: 17, style: .continuous
        )
    }
}

/// A change the agent made, as one line between the bubbles with Undo beside it; "Undone"
/// once taken back.
struct AgentChangeLine: View {
    let change: AgentConversation.Change
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark.circle")
                .textRole(.caption)
                .foregroundStyle(Theme.leaf)
                .accessibilityHidden(true)
            Text(change.summary)
                .textRole(.caption)
                .foregroundStyle(Theme.text3)
                .lineLimit(1)
            Text("·")
                .textRole(.caption)
                .foregroundStyle(Theme.text3)
                .accessibilityHidden(true)
            if change.undone {
                Text(AgentText.undone)
                    .textRole(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.text3)
            } else {
                Button(AgentText.undo, action: onUndo)
                    .buttonStyle(.plain)
                    .textRole(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.leaf)
                    .accessibilityLabel("Undo: \(change.summary)")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .accessibilityIdentifier("agent-change")
    }
}

/// Three dots in an agent bubble while it writes.
struct AgentTypingBubble: View {
    var body: some View {
        HStack(spacing: 4) {
            ForEach([1.0, 0.6, 0.35], id: \.self) { fade in
                Circle()
                    .fill(Theme.text3.opacity(fade))
                    .frame(width: 7, height: 7)
            }
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 13)
        .background(Theme.raised, in: shape)
        .overlay { shape.stroke(Theme.line, lineWidth: 1) }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Agent is typing")
        .accessibilityIdentifier("agent-typing")
    }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 17, bottomLeadingRadius: 4, bottomTrailingRadius: 17, topTrailingRadius: 17, style: .continuous)
    }
}

/// The field at the bottom: the This page chip while the page goes along, with its × to leave
/// it out; the words; Send. ↩ sends too. On a lens there is no page, so no chip.
struct AgentComposer: View {
    @ObservedObject var store: BudStore
    @State private var draft = ""

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 19, style: .continuous)
        HStack(spacing: 6) {
            if page != nil && store.agent.includesPage {
                chip
            }
            TextField(AgentText.placeholder, text: $draft)
                .textFieldStyle(.plain)
                .textStyle(AgentPanelText.bubble)
                .foregroundStyle(Theme.text)
                .onSubmit(send)
                .accessibilityIdentifier("agent-draft")
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .textRole(.label)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.onLeaf)
                    .frame(width: 28, height: 28)
                    .background(Theme.leafFill, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(AgentText.send)
            .accessibilityLabel(AgentText.send)
            .accessibilityIdentifier("agent-send")
        }
        .padding(.leading, 6)
        .padding([.vertical, .trailing], 4)
        .background(Theme.raised, in: shape)
        .overlay { shape.stroke(Theme.lineStrong, lineWidth: 1) }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .accessibilityIdentifier("agent-composer")
    }

    private var chip: some View {
        HStack(spacing: 4) {
            Image(systemName: "doc.text")
                .textStyle(AgentPanelText.chip)
                .accessibilityHidden(true)
            Text(AgentText.thisPage)
                .textStyle(AgentPanelText.chip)
                .lineLimit(1)
            Button { store.agent.includesPage = false } label: {
                Image(systemName: "xmark")
                    .textStyle(AgentPanelText.mark)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(AgentText.removePage)
            .accessibilityLabel(AgentText.removePage)
            .accessibilityIdentifier("agent-page-off")
        }
        .foregroundStyle(Theme.leaf)
        .padding(.vertical, 3)
        .padding(.leading, 7)
        .padding(.trailing, 3)
        .background(Theme.leafSoft, in: Capsule())
        .accessibilityIdentifier("agent-page")
    }

    /// The page the chip stands for: the bud's title and body, when Files shows a bud's page.
    private var page: AgentConversation.Page? {
        guard let id = store.page, let bud = store.tree.bud(id) else { return nil }
        return AgentConversation.Page(title: store.tree.title(of: id), body: bud.body)
    }

    private func send() {
        guard store.agent.send(draft, page: page) != nil else { return }
        draft = ""
    }
}
#endif
