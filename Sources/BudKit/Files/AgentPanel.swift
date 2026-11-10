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
                AgentSetupLine(store: store)
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

/// The bubbles, bottom-aligned and scrolling when there are more than fit. The content is at
/// least as tall as the thread's room, so a short chat sits at the bottom in the app and in a
/// still picture alike.
struct AgentThread: View {
    let conversation: AgentConversation
    let onUndo: (AgentConversation.Change.ID) -> Void

    var body: some View {
        let read = conversation.lastRead
        GeometryReader { geo in
            MaybeScroll {
                VStack(alignment: .leading, spacing: 3) {
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
                            if message.id == read {
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
                .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .bottom)
            }
            .defaultScrollAnchor(.bottom)
        }
        .accessibilityIdentifier("agent-thread")
    }
}

/// A bubble's outline: round but for the tail, at the bottom right of the person's and the
/// bottom left of the agent's.
func bubbleShape(mine: Bool) -> UnevenRoundedRectangle {
    UnevenRoundedRectangle(
        topLeadingRadius: 17, bottomLeadingRadius: mine ? 17 : 4,
        bottomTrailingRadius: mine ? 4 : 17, topTrailingRadius: 17, style: .continuous
    )
}

/// One bubble: the person's in leaf on the right with its tail at the bottom right, the agent's
/// raised on the left with its tail at the bottom left.
struct AgentBubble: View {
    let message: AgentConversation.Message

    private var mine: Bool { message.who == .person }

    var body: some View {
        let shape = bubbleShape(mine: mine)
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
        let shape = bubbleShape(mine: false)
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
}

/// The line above the composer that names the app and the model the agent runs with, as
/// "Claude Code · Fable 5.1" with a chevron; a click opens the picker. The picture renderer
/// cannot draw a popover, so a still picture shows the line alone.
struct AgentSetupLine: View {
    @ObservedObject var store: BudStore
    @Environment(\.stillPicture) private var still
    @State private var open = false

    var body: some View {
        HStack {
            Button { open.toggle() } label: {
                HStack(spacing: 3) {
                    Text(store.agentChoice.label)
                        .textRole(.caption)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .textStyle(AgentPanelText.mark)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(Theme.text3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(AgentText.pick)
            .accessibilityLabel(AgentText.pick)
            .accessibilityValue(store.agentChoice.label)
            .accessibilityIdentifier("agent-setup")
            .popover(isPresented: still ? .constant(false) : $open, arrowEdge: .bottom) {
                AgentSetupMenu(store: store, apps: store.agentApps.entries)
                #if os(iOS)
                .presentationCompactAdaptation(.popover)
                #endif
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
    }
}

/// The picker: the apps under App, each with whether it is installed and signed in, the ones
/// not found dimmed; the chosen app's models under Model, each with a word on what it is for;
/// a check beside what is chosen; and, while the chosen app is installed and signed in, a line
/// saying the agent runs on this Mac with the person's own account.
struct AgentSetupMenu: View {
    @ObservedObject var store: BudStore
    let apps: [AgentApps.Entry]

    var body: some View {
        let choice = store.agentChoice
        let chosen = apps.first { $0.app.id == choice.app }
        VStack(alignment: .leading, spacing: 1) {
            heading(AgentText.app)
            ForEach(apps) { entry in
                row(
                    entry.app.name, note: entry.status.line, chosen: entry.app.id == choice.app,
                    enabled: entry.status.isInstalled, id: "agent-app-\(entry.app.id)"
                ) { store.agentChoice.choose(entry.app) }
            }
            if let chosen {
                heading(AgentText.model).padding(.top, 6)
                ForEach(store.agentApps.models(for: chosen.app)) { model in
                    row(
                        model.name, note: model.note, chosen: model.id == choice.model,
                        enabled: chosen.status.isInstalled, id: "agent-model-\(model.id)"
                    ) { store.agentChoice.choose(model) }
                }
                if chosen.status == .installed(signedIn: true) {
                    Text(AgentText.runsHere)
                        .textRole(.caption)
                        .foregroundStyle(Theme.text3)
                        .padding(.horizontal, 8)
                        .padding(.top, 8)
                        .padding(.bottom, 3)
                        .accessibilityIdentifier("agent-runs-here")
                }
            }
        }
        .padding(5)
        .frame(width: 240, alignment: .leading)
        .accessibilityIdentifier("agent-setup-menu")
    }

    private func heading(_ title: String) -> some View {
        Text(title)
            .textRole(.eyebrow)
            .foregroundStyle(Theme.text3)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
    }

    private func row(_ title: String, note: String, chosen: Bool, enabled: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .textRole(.body)
                        .foregroundStyle(enabled ? Theme.text : Theme.text3)
                    if !note.isEmpty {
                        Text(note)
                            .textRole(.caption)
                            .foregroundStyle(Theme.text3)
                    }
                }
                Spacer(minLength: 8)
                if chosen {
                    Image(systemName: "checkmark")
                        .textRole(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(enabled ? Theme.leaf : Theme.text3)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityValue(chosen ? "Chosen" : "")
        .accessibilityIdentifier(id)
    }
}

/// The field at the bottom: the This page chip while the page goes along, with its × to leave
/// it out and a quiet one to bring it back; the words; Send. ↩ sends too and keeps the field,
/// asking for focus back on a phone, where Return lets the keyboard go. On a lens there is no
/// page, so no chip. The field is a system control the picture renderer does not draw, so a
/// still picture shows the words as plain text.
struct AgentComposer: View {
    @ObservedObject var store: BudStore
    @Environment(\.stillPicture) private var still
    @FocusState private var typing: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 19, style: .continuous)
        HStack(spacing: 6) {
            if page != nil {
                chip(on: store.agent.includesPage)
            }
            if still {
                Text(store.agent.draft.isEmpty ? AgentText.placeholder : store.agent.draft)
                    .textStyle(AgentPanelText.bubble)
                    .foregroundStyle(store.agent.draft.isEmpty ? Theme.text3 : Theme.text)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField(AgentText.placeholder, text: $store.agent.draft)
                    .textFieldStyle(.plain)
                    .textStyle(AgentPanelText.bubble)
                    .foregroundStyle(Theme.text)
                    .focused($typing)
                    .submitLabel(.send)
                    .onSubmit {
                        send()
                        DispatchQueue.main.async { typing = true }
                    }
                    .accessibilityIdentifier("agent-draft")
            }
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

    /// The chip: in leaf with its × while the page goes along; dimmed, with a + in its place,
    /// once taken off, so a click brings the page back.
    private func chip(on: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "doc.text")
                .textStyle(AgentPanelText.chip)
                .accessibilityHidden(true)
            Text(AgentText.thisPage)
                .textStyle(AgentPanelText.chip)
                .lineLimit(1)
            Button { store.agent.includesPage.toggle() } label: {
                Image(systemName: on ? "xmark" : "plus")
                    .textStyle(AgentPanelText.mark)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(on ? AgentText.removePage : AgentText.addPage)
            .accessibilityLabel(on ? AgentText.removePage : AgentText.addPage)
            .accessibilityIdentifier(on ? "agent-page-off" : "agent-page-on")
        }
        .foregroundStyle(on ? Theme.leaf : Theme.text3)
        .padding(.vertical, 3)
        .padding(.leading, 7)
        .padding(.trailing, 3)
        .background(on ? Theme.leafSoft : Theme.window, in: Capsule())
        .accessibilityIdentifier("agent-page")
        .accessibilityValue(on ? "On" : "Off")
    }

    /// The page the chip stands for: the bud's title and body, when Files shows a bud's page.
    private var page: AgentConversation.Page? {
        guard let id = store.page, let bud = store.tree.bud(id) else { return nil }
        return AgentConversation.Page(title: store.tree.title(of: id), body: bud.body)
    }

    private func send() {
        store.agent.sendDraft(page: page)
    }
}
#endif
