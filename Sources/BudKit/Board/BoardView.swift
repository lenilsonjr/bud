#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// The board of the center bud: its title and what is inside over the columns, Open first,
/// then one column per tag in the person's order, the slot that adds a column, then Done, and
/// Cancelled folded at the end behind "Show cancelled". A tag column dragged by its header is
/// drawn here, lifted under the pointer, and lands in the gap the drop line showed; its ⋯ menu
/// moves it or takes it off the board. A card dragged to another column lands there through
/// the store, which writes the tag or the state and offers to take it back.
struct BoardView: View {
    @ObservedObject var store: BudStore
    @Environment(\.compact) private var compact
    @Environment(\.stillPicture) private var still
    @Environment(\.stillBoardDrag) private var stillDrag
    @State private var showsCancelled = false
    /// The tag column in hand and where the pointer is, in this view's space.
    @State private var inHand: (tag: String, at: CGPoint)? = nil
    /// Where each tag column is, in this view's space, as the columns report it during a drag.
    @State private var frames: [String: CGRect] = [:]
    /// The column the card in hand hovers over, while it hovers.
    @State private var targeted: BoardColumn.Kind?

    static let space = "board"

    var body: some View {
        // Built once a render: the store's board is read from the whole tree.
        let board = store.board
        let pictures = BoardCardContext(states: store.pictures, now: store.now, calendar: store.calendar) { [weak store] id in
            await store?.loadPicture(of: id)
        }
        let tags = board.columns.compactMap(\.tag)
        let moving = inHand.map { BoardColumnDrag(tag: $0.tag, point: $0.at, drop: BoardColumnDrop.under($0.at, frames: frames, tags: tags)) }
        let edit = BoardColumnEdit(columns: BoardColumns(tags: tags)) { [weak store] item, tag in
            guard let store else { return }
            store.editBoardColumns(of: store.center) { item.apply(to: &$0, for: tag) }
        }
        VStack(alignment: .leading, spacing: 16) {
            head(board)
            columns(board, pictures: pictures, edit: edit)
        }
        .padding(.top, 20)
        .padding(.horizontal, compact ? 16 : 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surface)
        .coordinateSpace(name: Self.space)
        .environment(\.boardColumnDragging, BoardColumnDragging(
            drag: moving,
            placed: { frames[$0] = $1 },
            moved: { tag, point in inHand = (tag, point) },
            ended: { tag, point in
                let drag = BoardColumnDrag(tag: tag, point: point, drop: BoardColumnDrop.under(point, frames: frames, tags: tags))
                if let index = drag.target(in: tags) { store.moveBoardColumn(tag, to: index, of: store.center) }
                inHand = nil
                frames = [:]
            },
            released: {
                inHand = nil
                frames = [:]
            }
        ))
        .overlay(alignment: .topLeading) {
            if let inHand { BoardColumnLifted(tag: inHand.tag).offset(x: inHand.at.x - 8, y: inHand.at.y - 8) }
        }
        .onChange(of: store.center) { _, _ in
            showsCancelled = false
            inHand = nil
        }
    }

    /// The bud's title with "Everything inside · 17" beside it.
    private func head(_ board: Board) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(board.title)
                .textRole(.title)
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            Text(board.scope)
                .textStyle(TextStyle(typeface: .text, size: 12, weight: 400))
                .foregroundStyle(Theme.text3)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    /// The columns side by side, the add slot before Done, scrolling sideways when the window
    /// is narrower than they are.
    @ViewBuilder private func columns(_ board: Board, pictures: BoardCardContext, edit: BoardColumnEdit) -> some View {
        let row = HStack(alignment: .top, spacing: 12) {
            ForEach(board.columns) { column in
                if column.kind == .done { BoardAddColumn(store: store) }
                BoardColumnView(column: column, pictures: pictures, edit: column.tag == nil ? nil : edit, hover: hover(on: column.kind, in: board))
                    .frame(width: column.kind == .done ? 220 : 232)
                    .budDrop(onTarget: { target(column.kind, $0) }) { store.drop($0, on: column.kind) }
            }
            cancelled(board, pictures: pictures)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        if still {
            row.frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            ScrollView(.horizontal, showsIndicators: false) { row }
        }
    }

    /// What a column shows of the drag: in a still picture, the card the environment lifts over
    /// the column it names; live, whether the card in hand hovers over it.
    private func hover(on kind: BoardColumn.Kind, in board: Board) -> BoardCardHover? {
        if still {
            guard let stillDrag, stillDrag.over == kind else { return nil }
            return BoardCardHover(targeted: true, lifted: board.card(stillDrag.card))
        }
        return targeted == kind ? BoardCardHover(targeted: true) : nil
    }

    private func target(_ kind: BoardColumn.Kind, _ hovering: Bool) {
        if hovering {
            targeted = kind
        } else if targeted == kind {
            targeted = nil
        }
    }

    /// Cancelled: a 40 pt stub with its count until shown, then a column like Done.
    @ViewBuilder private func cancelled(_ board: Board, pictures: BoardCardContext) -> some View {
        if showsCancelled {
            BoardColumnView(column: board.cancelled, pictures: pictures, hover: hover(on: .cancelled, in: board)) { showsCancelled = false }
                .frame(width: 220)
                .budDrop(onTarget: { target(.cancelled, $0) }) { store.drop($0, on: .cancelled) }
        } else {
            Button { showsCancelled = true } label: {
                VStack(spacing: 8) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.text3)
                        .frame(width: 14, height: 14)
                    Text("\(board.cancelled.cards.count)")
                        .textStyle(BoardColumnView.count)
                        .foregroundStyle(Theme.text3)
                }
                .padding(.vertical, 12)
                .frame(width: 40)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(Theme.sidebar, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show cancelled")
            .accessibilityLabel("Show cancelled")
            .accessibilityIdentifier("show-cancelled")
        }
    }
}

/// What the cards need of the store, read once a render and handed down, so a card does not
/// watch the store: the pictures known so far, the day, and how to ask for a picture.
struct BoardCardContext {
    var states: [UUID: BoardPictureState]
    var now: Date
    var calendar: Calendar
    var load: (UUID) async -> Void

    func state(of id: UUID) -> BoardPictureState { states[id] ?? .unknown }
}

/// One column: its header, then its cards top to bottom. Open, Done and Cancelled sit on the
/// sidebar tone with an eyebrow and a glyph; a tag column is a hairline around its tag chip,
/// with the ⋯ menu that moves it or takes it off the board. Dragging a tag column's chip
/// lifts the column: its place fades, and the leaf drop line shows beside the column it would
/// land before, or after the last one. On a phone the menu stays and there is no drag.
struct BoardColumnView: View {
    let column: BoardColumn
    let pictures: BoardCardContext
    /// How a tag column edits the board; nil on Open, Done and Cancelled.
    var edit: BoardColumnEdit? = nil
    /// The card in hand over this column: the drop hint at the top, and in a still picture the
    /// lifted card itself; nil while nothing hovers.
    var hover: BoardCardHover? = nil
    /// Folds Cancelled back behind its stub; nil on the other columns.
    var onHide: (() -> Void)? = nil
    @Environment(\.stillPicture) private var still
    @Environment(\.compact) private var compact
    @Environment(\.boardColumnDragging) private var dragging
    @State private var menuOpen = false
    @GestureState private var holding = false

    /// The count beside a header's word and on the Cancelled stub: 11 pt regular.
    static let count = TextStyle(typeface: .text, size: 11, weight: 400)
    /// "OPEN", "DONE", "CANCELLED": 11 pt bold, tracked a little wider than the eyebrow is tall.
    static let word = TextStyle(typeface: .text, size: 11, weight: 700, tracking: 1.4, uppercase: true)

    var body: some View {
        let frame = VStack(alignment: .leading, spacing: 8) {
            header
            if still {
                cards
            } else {
                ScrollView(showsIndicators: false) { cards }
            }
        }
        .padding(.top, 10)
        .padding([.horizontal, .bottom], 8)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(column.isFixed ? Theme.sidebar : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            if hover?.targeted == true {
                RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.leafLine, lineWidth: 1.5)
            } else if !column.isFixed {
                RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line, lineWidth: 1)
            }
        }
        .overlay(alignment: .top) { liftedCard }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(column.title)
        if let tag = column.tag, let edit {
            lifted(frame, tag: tag, tags: edit.columns.tags)
        } else {
            frame
        }
    }

    /// A tag column as a drag lifts it: faded while in hand, the drop line on the edge it would
    /// land at, its place told to the board as a drag begins, and the grip let go.
    private func lifted(_ frame: some View, tag: String, tags: [String]) -> some View {
        let line = dragging.drag?.line(on: tag, in: tags)
        return frame
            .opacity(dragging.drag?.tag == tag ? 0.3 : 1)
            .overlay(alignment: .leading) { if line == .before { BoardColumnDropLine().offset(x: -10) } }
            .overlay(alignment: .trailing) { if line == .after { BoardColumnDropLine().offset(x: 10) } }
            .background(probe(tag))
            .onChange(of: holding) { _, now in if !now { dragging.released() } }
    }

    /// Tells the board where this column is as a drag begins, so the drop line can find its gap.
    private func probe(_ tag: String) -> some View {
        GeometryReader { geo in
            Color.clear.onChange(of: dragging.drag?.tag) { _, now in
                guard now != nil else { return }
                dragging.placed(tag, geo.frame(in: .named(BoardView.space)))
            }
        }
    }

    private var cards: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            if hover?.targeted == true {
                BoardDropHint(column: column.kind)
            }
            ForEach(column.cards) { card in
                BoardCardView(card: card, picture: pictures.state(of: card.id), now: pictures.now, calendar: pictures.calendar) {
                    await pictures.load(card.id)
                }
                .boardDraggable(card.id)
            }
        }
    }

    /// The card a still picture holds over this column, raised and turned a little, the way the
    /// system's preview carries a live one.
    @ViewBuilder private var liftedCard: some View {
        if let card = hover?.lifted {
            BoardCardView(card: card, picture: pictures.state(of: card.id), now: pictures.now, calendar: pictures.calendar) {}
                .frame(width: 232)
                .rotationEffect(.degrees(-2))
                .shadow(color: Theme.shadowStrong, radius: 14, y: 8)
                .offset(x: -36, y: 64)
                .allowsHitTesting(false)
        }
    }

    private var header: some View {
        HStack(spacing: 7) {
            if let tag = column.tag {
                chip(tag)
            } else {
                glyph
                Text(column.title)
                    .textStyle(Self.word)
                    .foregroundStyle(Theme.text2)
            }
            Text("\(column.cards.count)")
                .textStyle(Self.count)
                .foregroundStyle(Theme.text3)
            Spacer(minLength: 0)
            if let tag = column.tag, let edit {
                menuButton(tag, edit: edit)
            }
            if let onHide {
                Button(action: onHide) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.text3)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Hide cancelled")
                .accessibilityLabel("Hide cancelled")
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
    }

    /// The tag chip, and the grip that lifts the column: a drag on it, where the board can take
    /// one, in the board's space, ahead of the row's sideways scroll so the pan does not take
    /// it on an iPad. A phone scrolls the columns sideways instead.
    @ViewBuilder private func chip(_ tag: String) -> some View {
        let mark = BoardTagChip(tag: tag).contentShape(Rectangle())
        if edit != nil, !compact, !still {
            mark.highPriorityGesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .named(BoardView.space))
                    .updating($holding) { _, state, _ in state = true }
                    .onChanged { dragging.moved(tag, $0.location) }
                    .onEnded { dragging.ended(tag, $0.location) }
            )
        } else {
            mark
        }
    }

    /// The ⋯ that opens the column's menu. The picture renderer cannot draw a popover, so a
    /// still picture shows the button alone.
    private func menuButton(_ tag: String, edit: BoardColumnEdit) -> some View {
        Button { menuOpen.toggle() } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.text3)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("#\(tag) column menu")
        .accessibilityLabel("#\(tag) column menu")
        .accessibilityIdentifier("board-column-menu-\(tag)")
        .popover(isPresented: still ? .constant(false) : $menuOpen, arrowEdge: .bottom) {
            BoardColumnMenu(tag: tag, edit: edit) { menuOpen = false }
            #if os(iOS)
            .presentationCompactAdaptation(.popover)
            #endif
        }
    }

    /// Open's empty circle, Done's ticked one in leaf, Cancelled's crossed one.
    private var glyph: some View {
        let (name, tone): (String, Color) = switch column.kind {
        case .done: ("checkmark.circle", Theme.leaf)
        case .cancelled: ("xmark.circle", Theme.text3)
        default: ("circle", Theme.text3)
        }
        return Image(systemName: name)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(tone)
            .frame(width: 14, height: 14)
    }
}
#endif
