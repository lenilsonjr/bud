#if canImport(SwiftUI) && os(tvOS)
import SwiftUI

/// Files on Apple TV (G16's third tab): the pages on the left, the rows of the chosen one on the
/// right, drawn for a viewer at three metres. A click goes inside a bud with children or reads
/// a leaf; Play/Pause ticks the to-do in focus; press and hold opens the bud menu; Menu steps
/// out, page by page, then to the pages column, then back to Canvas.
struct TVFilesTab: View {
    @ObservedObject var store: BudStore
    let onLeave: () -> Void
    let onOpen: (UUID) -> Void
    @State private var page: TVFilesPage = .inbox
    @State private var inside: [UUID] = []
    @State private var adding: TVAddTarget? = nil
    @FocusState private var focused: Focus?

    enum Focus: Hashable {
        case page(TVFilesPage)
        case row(UUID)
    }

    private static let title = TextStyle(typeface: .display, size: 64, weight: 500)
    private static let trail = TextStyle(typeface: .text, size: 24, weight: 400)
    private static let empty = TextStyle(typeface: .text, size: 26, weight: 400)

    private var place: UUID { inside.last ?? rootID }
    private var rows: [TVFilesRow] { TVFilesText.rows(page, in: store.tree, inside: place) }

    var body: some View {
        HStack(alignment: .top, spacing: 80) {
            pages
                .frame(width: 440)
                .focusSection()
            list
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .focusSection()
        }
        .padding(.top, 30)
        .padding(.horizontal, 160)
        .padding(.bottom, 90)
        .sheet(item: $adding) { target in TVCaptureSheet(store: store, parent: target.id) }
        .onExitCommand(perform: stepOut)
        .onPlayPauseCommand(perform: tickFocused)
        .onChange(of: page) { _, _ in inside = [] }
    }

    /// The pages column: a glyph, the name, and the count the Mac sidebar shows.
    private var pages: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(TVFilesPage.allCases, id: \.self) { item in
                TVPageRow(
                    page: item, count: TVFilesText.count(item, in: store.tree),
                    chosen: page == item, lit: focused == .page(item)
                ) { page = item }
                .focused($focused, equals: .page(item))
            }
            Spacer(minLength: 0)
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Text(inside.isEmpty ? page.rawValue : store.tree.title(of: place))
                    .textStyle(Self.title)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                if !inside.isEmpty {
                    Text((["Everything"] + TVFilesText.trail(inside: place, in: store.tree).dropLast()).joined(separator: " › "))
                        .textStyle(Self.trail)
                        .foregroundStyle(Theme.text2)
                        .lineLimit(1)
                }
            }
            .padding(.bottom, 14)
            if rows.isEmpty {
                Text(page.empty)
                    .textStyle(Self.empty)
                    .foregroundStyle(Theme.text3)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(rows, id: \.id) { row in
                            TVBudRow(row: row, lit: focused == .row(row.id)) { click(row) }
                                .focused($focused, equals: .row(row.id))
                                .budMenu(row.id, store: store, onAdd: { adding = TVAddTarget(id: row.id) }, onOpen: { onOpen(row.id) })
                        }
                    }
                    .padding(.vertical, 30)
                }
                .scrollClipDisabled()
            }
        }
    }

    private func click(_ row: TVFilesRow) {
        if row.opens {
            inside.append(row.id)
        } else {
            onOpen(row.id)
        }
    }

    private func tickFocused() {
        guard case let .row(id) = focused, store.tree.bud(id)?.isTodo == true else { return }
        store.toggle(id)
    }

    /// Menu: out of the bud on show, then from the rows to the pages, then to Canvas.
    private func stepOut() {
        if !inside.isEmpty {
            inside.removeLast()
        } else if case .row = focused {
            focused = .page(page)
        } else {
            onLeave()
        }
    }
}

/// One page in the left column: 84 pt, the glyph in leaf, the name, the count at the end. The
/// chosen page keeps a soft wash; the focused one the amethyst ring.
struct TVPageRow: View {
    let page: TVFilesPage
    let count: Int?
    let chosen: Bool
    let lit: Bool
    let action: () -> Void

    private static let name = TextStyle(typeface: .text, size: 29, weight: 500)
    private static let count = TextStyle(typeface: .text, size: 22, weight: 600)

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        Button(action: action) {
            HStack(spacing: 20) {
                Image(systemName: page.symbol)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Theme.leaf)
                    .frame(width: 40)
                Text(page.rawValue)
                    .textStyle(Self.name)
                    .foregroundStyle(chosen ? Theme.text : Theme.text2)
                Spacer(minLength: 0)
                if let count, count > 0 {
                    Text("\(count)")
                        .textStyle(Self.count)
                        .foregroundStyle(Theme.text3)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 26)
            .frame(maxWidth: .infinity)
            .frame(height: 84)
            .background(lit ? Theme.amethystSoft : (chosen ? Theme.raised : .clear), in: shape)
            .overlay(shape.stroke(lit ? Theme.amethyst : .clear, lineWidth: 2))
            .shadow(color: lit ? Theme.amethyst.opacity(0.35) : .clear, radius: lit ? 24 : 0)
        }
        .buttonStyle(.tvBare)
        .animation(.easeOut(duration: 0.2), value: lit)
    }
}

/// One bud as a TV row: the 112 pt raised row of Devices, with the kind mark in a lit square,
/// the title, the breadcrumb or kind under it, and the tag at the end.
struct TVBudRow: View {
    let row: TVFilesRow
    let lit: Bool
    let action: () -> Void

    private static let title = TextStyle(typeface: .text, size: 30, weight: 500)
    private static let caption = TextStyle(typeface: .text, size: 22, weight: 400)
    private static let tag = TextStyle(typeface: .text, size: 20, weight: 600)

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        Button(action: action) {
            HStack(spacing: 26) {
                mark
                    .frame(width: 60, height: 60)
                    .background(Theme.lit, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 6) {
                    Text(row.title)
                        .strikethrough(row.isDone)
                        .textStyle(Self.title)
                        .foregroundStyle(row.isDone ? Theme.text3 : Theme.text)
                        .lineLimit(1)
                    Text(row.caption)
                        .textStyle(Self.caption)
                        .foregroundStyle(Theme.text3)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let label = TVFilesText.label(row.tag) {
                    Text(label)
                        .textStyle(Self.tag)
                        .foregroundStyle(due ? Theme.pistil : Theme.text2)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(due ? Theme.pistilSoft : Theme.lit, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                if row.opens {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Theme.text3)
                }
            }
            .padding(.horizontal, 30)
            .frame(maxWidth: .infinity)
            .frame(height: 112)
            .background(lit ? Theme.amethystSoft : Theme.raised, in: shape)
            .overlay(shape.stroke(lit ? Theme.amethyst : Theme.line, lineWidth: lit ? 2 : 1))
            .shadow(color: lit ? Theme.amethyst.opacity(0.35) : .clear, radius: lit ? 24 : 0)
        }
        .buttonStyle(.tvBare)
        .animation(.easeOut(duration: 0.2), value: lit)
    }

    private var due: Bool {
        if case .due = row.tag { return true }
        return false
    }

    /// The box of a to-do, ticked when done, or the dot of a note.
    @ViewBuilder private var mark: some View {
        if row.isTodo {
            Image(systemName: row.isDone ? "checkmark.square.fill" : "square")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(row.isDone ? Theme.leaf : Theme.text2)
        } else {
            Circle().fill(Theme.leaf).frame(width: 12, height: 12)
        }
    }
}
#endif
