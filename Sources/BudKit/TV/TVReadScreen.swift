#if canImport(SwiftUI) && os(tvOS)
import SwiftUI

/// One bud read on Apple TV, full screen: the trail, the title in the display face, the kind and
/// dates, the next step inside it, the body as paragraphs and lists, and the children as TV
/// rows on the right. A click on a child reads it in turn; Menu steps back, then closes;
/// Play/Pause closes the to-do in focus, or the next step. Press and hold on the title or a row
/// opens the bud menu.
struct TVReadScreen: View {
    @ObservedObject var store: BudStore
    let start: UUID
    let close: () -> Void
    @State private var stack: [UUID] = []
    @State private var adding: TVAddTarget? = nil
    @FocusState private var focused: Focus?

    enum Focus: Hashable {
        case title
        case body
        case row(UUID)
    }

    private static let trail = TextStyle(typeface: .text, size: 24, weight: 400)
    private static let title = TextStyle(typeface: .display, size: 64, weight: 500)
    private static let kind = TextStyle(typeface: .text, size: 24, weight: 400)
    private static let step = TextStyle(typeface: .text, size: 28, weight: 500)
    private static let hint = TextStyle(typeface: .text, size: 22, weight: 400)
    private static let heading = TextStyle(typeface: .display, size: 38, weight: 500)
    private static let paragraph = TextStyle(typeface: .text, size: 30, weight: 400)
    private static let eyebrow = TextStyle(typeface: .text, size: 20, weight: 700, tracking: 1.6, uppercase: true)

    private var id: UUID { stack.last ?? start }
    private var rows: [TVFilesRow] { TVFilesText.rows(.everything, in: store.tree, inside: id) }

    var body: some View {
        Group {
            if let bud = store.tree.bud(id) {
                // 820 for the page, 800 for the children: a row's title and tag fit at three metres.
                HStack(alignment: .top, spacing: 60) {
                    page(bud)
                        .frame(width: 820, alignment: .topLeading)
                        .focusSection()
                    children
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .focusSection()
                }
                .padding(.top, 80)
                .padding(.horizontal, 120)
                .padding(.bottom, 90)
            } else {
                // The bud went while the screen was up (trashed from the menu, or synced away).
                Color.clear.onAppear(perform: stepBack)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.window.ignoresSafeArea())
        .textRole(.body)
        .foregroundStyle(Theme.text)
        .sheet(item: $adding) { target in TVCaptureSheet(store: store, parent: target.id) }
        .onExitCommand(perform: stepBack)
        .onPlayPauseCommand(perform: playPause)
        .onAppear { focused = .title }
    }

    private func page(_ bud: Bud) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 26) {
                let crumbs = ["Everything"] + store.tree.breadcrumb(of: id)
                Text(crumbs.joined(separator: " › "))
                    .textStyle(Self.trail)
                    .foregroundStyle(Theme.text2)
                    .lineLimit(1)
                titleBlock(bud)
                if let step = TVReadText.nextStep(in: store.tree, under: id) {
                    HStack(spacing: 14) {
                        Image(systemName: "scope")
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(Theme.leaf)
                        Text(step)
                            .textStyle(Self.step)
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .background(Theme.leafSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                if !bud.body.isEmpty { bodyBlocks(bud.body) }
                if let hint = TVReadText.playPauseHint(in: store.tree, under: id) {
                    Text(hint)
                        .textStyle(Self.hint)
                        .foregroundStyle(Theme.text3)
                        .padding(.top, 10)
                }
            }
            .padding(.vertical, 20)
        }
        .scrollClipDisabled()
    }

    /// The title is a button so the remote can rest on it and press and hold opens the menu.
    private func titleBlock(_ bud: Bud) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        let lit = focused == .title
        return Button {} label: {
            VStack(alignment: .leading, spacing: 10) {
                Text(bud.text)
                    .strikethrough(bud.isDone)
                    .textStyle(Self.title)
                    .foregroundStyle(bud.isDone ? Theme.text3 : Theme.text)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(TVReadText.kindLine(bud))
                    .textStyle(Self.kind)
                    .foregroundStyle(Theme.text2)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(lit ? Theme.amethystSoft : .clear, in: shape)
            .overlay(shape.stroke(lit ? Theme.amethyst : .clear, lineWidth: 2))
            .shadow(color: lit ? Theme.amethyst.opacity(0.35) : .clear, radius: lit ? 24 : 0)
        }
        .buttonStyle(.tvBare)
        .focused($focused, equals: .title)
        .budMenu(id, store: store, onAdd: { adding = TVAddTarget(id: id) })
        .padding(.horizontal, -24)
        .animation(.easeOut(duration: 0.2), value: lit)
    }

    /// The body as the Mac draws it, scaled for the room; focusable so the remote scrolls it,
    /// with the ring drawn around it while it holds the focus.
    private func bodyBlocks(_ source: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        let lit = focused == .body
        return VStack(alignment: .leading, spacing: 22) {
            ForEach(Array(MarkdownBlocks.parse(source).enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(_, let text):
                    Text(MarkdownBlocks.inline(text))
                        .textStyle(Self.heading)
                        .foregroundStyle(Theme.text)
                        .padding(.top, 8)
                case .bullets(let items):
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .firstTextBaseline, spacing: 16) {
                                Circle()
                                    .fill(Theme.leaf)
                                    .frame(width: 10, height: 10)
                                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 6 }
                                paragraph(item)
                            }
                        }
                    }
                case .paragraph(let text):
                    paragraph(text)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(lit ? Theme.amethystSoft : .clear, in: shape)
        .overlay(shape.stroke(lit ? Theme.amethyst : .clear, lineWidth: 2))
        .shadow(color: lit ? Theme.amethyst.opacity(0.35) : .clear, radius: lit ? 24 : 0)
        .padding(.horizontal, -24)
        .focusable()
        .focused($focused, equals: .body)
        .animation(.easeOut(duration: 0.2), value: lit)
    }

    private func paragraph(_ text: String) -> some View {
        Text(MarkdownBlocks.inline(text))
            .textStyle(Self.paragraph)
            .lineSpacing(30 * 0.45)
            .foregroundStyle(Theme.text2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var children: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(TVReadText.insideLine(in: store.tree, under: id))
                .textStyle(Self.eyebrow)
                .foregroundStyle(Theme.leaf)
                .padding(.bottom, 4)
            if rows.isEmpty {
                Text("Press and hold the title for Add inside.")
                    .textStyle(Self.hint)
                    .foregroundStyle(Theme.text3)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(rows, id: \.id) { row in
                            TVBudRow(row: row, lit: focused == .row(row.id)) { read(row.id) }
                                .focused($focused, equals: .row(row.id))
                                .budMenu(row.id, store: store, onAdd: { adding = TVAddTarget(id: row.id) }, onOpen: { read(row.id) })
                        }
                    }
                    .padding(.vertical, 30)
                }
                .scrollClipDisabled()
            }
        }
    }

    /// Play/Pause closes the to-do in focus, or the next step inside the bud, or the bud itself.
    private func playPause() {
        if case let .row(child) = focused, store.tree.bud(child)?.isTodo == true {
            store.tvTick(child)
        } else if let step = store.tree.nextStep(under: id), step.id != id {
            store.tvTick(step.id)
        } else {
            store.tvTick(id)
        }
    }

    /// A child takes the screen, its title in focus so Menu and Play/Pause know where they are.
    private func read(_ child: UUID) {
        stack.append(child)
        focused = .title
    }

    private func stepBack() {
        if stack.isEmpty {
            close()
        } else {
            let left = stack.removeLast()
            focused = .row(left)
        }
    }
}
#endif
