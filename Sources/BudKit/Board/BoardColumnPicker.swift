#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// The slot after the last tag column, before Done: a 40 pt stub with a plus, where the next
/// column will stand. A click gathers what the picker reads, once, and opens it. The picture
/// renderer cannot draw a popover, so a still picture shows the stub alone and draws the
/// picker as a plain view.
struct BoardAddColumn: View {
    @ObservedObject var store: BudStore
    @Environment(\.stillPicture) private var still
    @State private var open = false
    @State private var source = BoardTagSource(columns: BoardColumns(tags: []), carried: [], counts: [])

    var body: some View {
        Button {
            if !open { source = store.boardTagSource(of: store.center) }
            open.toggle()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.leaf)
                .frame(width: 14, height: 14)
                .padding(.vertical, 12)
                .frame(width: 40)
                .frame(maxHeight: .infinity, alignment: .top)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(Theme.line)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(BoardColumnText.add)
        .accessibilityLabel(BoardColumnText.add)
        .accessibilityIdentifier("add-column")
        .popover(isPresented: still ? .constant(false) : $open, arrowEdge: .bottom) {
            BoardColumnPicker(store: store, id: store.center, source: source) { open = false }
            #if os(iOS)
            .presentationCompactAdaptation(.popover)
            #endif
        }
    }
}

/// Find or create a tag: the search line, then On this board and Other tags as
/// `BoardTagChoices` lists them from the source gathered as the picker opened, each tag a
/// chip, a check on one that has a column already, and New tag column last, lit once a new
/// tag is typed. ↑↓ move, ↩ picks, Esc closes. A pick adds the column at the end and closes
/// the picker. The field is a system control the picture renderer does not draw, so a still
/// picture shows its words as plain text.
struct BoardColumnPicker: View {
    @ObservedObject var store: BudStore
    let id: UUID
    let source: BoardTagSource
    var onChoose: () -> Void = {}
    @Environment(\.stillPicture) private var still
    @Environment(\.dismiss) private var dismiss
    @State private var query: String
    @State private var pick = 0
    @FocusState private var focused: Bool

    init(store: BudStore, id: UUID, source: BoardTagSource, query: String = "", onChoose: @escaping () -> Void = {}) {
        self.store = store
        self.id = id
        self.source = source
        self.onChoose = onChoose
        _query = State(initialValue: query)
    }

    var body: some View {
        let choices = BoardTagChoices.rows(for: query, in: source)
        let order = choices.pickable
        VStack(alignment: .leading, spacing: 2) {
            field(choices)
            if !choices.onBoard.isEmpty { group(BoardColumnText.onBoard, choices.onBoard, order: order) }
            if !choices.others.isEmpty { group(BoardColumnText.others, choices.others, order: order) }
            createRow(choices.create, picked: pick == order.count)
        }
        .padding(6)
        .frame(width: 260, alignment: .leading)
        .onAppear { focused = true }
        .onChange(of: query) { _, _ in pick = 0 }
        .onKey(.rowUp) { _ in pick = max(0, pick - 1); return .handled }
        .onKey(.rowDown) { _ in pick = max(0, min(choices.count - 1, pick + 1)); return .handled }
        .onKey(.close) { _ in dismiss(); return .handled }
        .accessibilityIdentifier("board-column-picker")
    }

    private func field(_ choices: BoardTagChoices) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .textRole(.caption)
                .foregroundStyle(Theme.text3)
                .accessibilityHidden(true)
            if still {
                Text(query.isEmpty ? BoardColumnText.find : query)
                    .foregroundStyle(query.isEmpty ? Theme.text3 : Theme.text)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField(BoardColumnText.find, text: $query)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit { take(choices) }
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
                    .accessibilityIdentifier("board-column-query")
            }
        }
        .textRole(.body)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).stroke(Theme.leafLine, lineWidth: 1))
        .padding(.bottom, 4)
    }

    /// ↩ takes the lit row: a tag, or the new tag column after the last.
    private func take(_ choices: BoardTagChoices) {
        let order = choices.pickable
        if order.indices.contains(pick) {
            choose(order[pick].tag)
        } else if pick == order.count, let tag = choices.create {
            choose(tag)
        }
    }

    private func choose(_ tag: String) {
        store.addBoardColumn(tag, of: id)
        onChoose()
    }

    private func group(_ title: String, _ rows: [BoardTagChoices.Row], order: [BoardTagChoices.Row]) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .textRole(.eyebrow)
                .foregroundStyle(Theme.text3)
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 4)
            ForEach(rows, id: \.self) { row in
                let index = order.firstIndex(of: row)
                Button { choose(row.tag) } label: { line(row, picked: index == pick) }
                    .buttonStyle(.plain)
                    .disabled(row.hasColumn)
            }
        }
    }

    private func line(_ row: BoardTagChoices.Row, picked: Bool) -> some View {
        HStack(spacing: 8) {
            BoardTagChip(tag: row.tag, quiet: row.hasColumn)
            Spacer(minLength: 8)
            if row.hasColumn {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.text3)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(picked ? Theme.leafSoft : .clear, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .contentShape(Rectangle())
    }

    /// "New tag column #blocked" in leaf once a new tag is typed; the words alone, quiet, as
    /// the hint of what typing does.
    private func createRow(_ tag: String?, picked: Bool) -> some View {
        Button { if let tag { choose(tag) } } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tag == nil ? Theme.text3 : Theme.leaf)
                    .frame(width: 14)
                    .accessibilityHidden(true)
                Text(tag.map(BoardColumnText.create) ?? BoardColumnText.newColumn)
                    .textRole(.body)
                    .foregroundStyle(tag == nil ? Theme.text3 : Theme.leaf)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(picked && tag != nil ? Theme.leafSoft : .clear, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(tag == nil)
        .padding(.top, 4)
        .overlay(alignment: .top) { Divider() }
        .accessibilityIdentifier("new-tag-column")
    }
}

/// A tag as the board writes it: "#doing" in leaf on the leaf wash, as a column's header
/// reads it; quiet, in the third tone on the raised wash, for one the picker lists but cannot
/// pick again.
struct BoardTagChip: View {
    let tag: String
    var quiet = false

    var body: some View {
        Text("#\(tag)")
            .textStyle(TextStyle(typeface: .text, size: 12, weight: 600))
            .foregroundStyle(quiet ? Theme.text3 : Theme.leaf)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(quiet ? Theme.raised : Theme.leafSoft, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }
}

/// What a tag column's header needs to edit the board: the columns as they stand, for which
/// menu items do anything, and how to apply one. Nil on Open, Done and Cancelled.
struct BoardColumnEdit {
    var columns: BoardColumns
    var apply: (BoardColumnMenuItem, String) -> Void
}

/// The ⋯ menu of a tag column, its items as `BoardColumnMenuItem` lists them: moving it, then
/// taking it off the board. Each edits the columns alone; the buds keep their tags.
struct BoardColumnMenu: View {
    let tag: String
    let edit: BoardColumnEdit
    var onChoose: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(BoardColumnMenuItem.allCases, id: \.self) { item in
                if item.startsGroup { Divider().padding(.vertical, 3) }
                row(item)
            }
        }
        .padding(5)
        .frame(width: 180, alignment: .leading)
        .accessibilityIdentifier("board-column-menu")
    }

    private func row(_ item: BoardColumnMenuItem) -> some View {
        let enabled = item.isEnabled(for: tag, in: edit.columns)
        return Button {
            edit.apply(item, tag)
            onChoose()
        } label: {
            Text(item.title)
                .textRole(.body)
                .foregroundStyle(enabled ? Theme.text : Theme.text3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// What a column needs from the board while one is in hand: the drag itself, and the way to
/// say where it is, where the pointer went, where it let go, and that the grip opened, dropped
/// or cancelled. The board sets it. Two are equal when the column in hand and its gap are: the
/// pointer's point is the board's own to draw, so the columns do not redraw as it moves.
struct BoardColumnDragging: Equatable {
    var drag: BoardColumnDrag? = nil
    var placed: (String, CGRect) -> Void = { _, _ in }
    var moved: (String, CGPoint) -> Void = { _, _ in }
    var ended: (String, CGPoint) -> Void = { _, _ in }
    var released: () -> Void = {}

    static func == (a: BoardColumnDragging, b: BoardColumnDragging) -> Bool {
        a.drag?.tag == b.drag?.tag && a.drag?.drop == b.drag?.drop
    }
}

private struct BoardColumnDraggingKey: EnvironmentKey {
    static let defaultValue = BoardColumnDragging()
}

extension EnvironmentValues {
    var boardColumnDragging: BoardColumnDragging {
        get { self[BoardColumnDraggingKey.self] }
        set { self[BoardColumnDraggingKey.self] = newValue }
    }
}

/// The leaf line a dragged column lands beside: a dot at its top and a line down the column.
struct BoardColumnDropLine: View {
    var body: some View {
        VStack(spacing: 0) {
            Circle().fill(Theme.leaf).frame(width: 8, height: 8)
            Capsule().fill(Theme.leaf).frame(width: 2)
        }
        .frame(width: 8)
        .padding(.vertical, 10)
        .accessibilityHidden(true)
    }
}

/// The column in hand, lifted under the pointer: its tag chip on a raised card with the leaf
/// line around it, a little tilted.
struct BoardColumnLifted: View {
    let tag: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
        BoardTagChip(tag: tag)
            .padding(12)
            .frame(width: 232, alignment: .leading)
            .background(Theme.raised, in: shape)
            .overlay(shape.strokeBorder(Theme.leafLine))
            .shadow(color: Theme.shadowStrong.opacity(0.5), radius: 20, y: 18)
            .rotationEffect(.degrees(-2), anchor: .topLeading)
            .opacity(0.97)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
#endif
