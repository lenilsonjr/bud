#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// The board of the center bud: its title and what is inside over the columns, Open first,
/// then one column per tag in the person's order, then Done, and Cancelled folded at the end
/// behind "Show cancelled". The cards are read only this round: nothing drags between columns
/// and no column is added here.
struct BoardView: View {
    @ObservedObject var store: BudStore
    @Environment(\.compact) private var compact
    @Environment(\.stillPicture) private var still
    @State private var showsCancelled = false

    var body: some View {
        // Built once a render: the store's board is read from the whole tree.
        let board = store.board
        let pictures = BoardCardContext(states: store.pictures, now: store.now) { [weak store] id in
            await store?.loadPicture(of: id)
        }
        VStack(alignment: .leading, spacing: 16) {
            head(board)
            columns(board, pictures: pictures)
        }
        .padding(.top, 20)
        .padding(.horizontal, compact ? 16 : 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surface)
        .onChange(of: store.center) { _, _ in showsCancelled = false }
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

    /// The columns side by side, scrolling sideways when the window is narrower than they are.
    @ViewBuilder private func columns(_ board: Board, pictures: BoardCardContext) -> some View {
        let row = HStack(alignment: .top, spacing: 12) {
            ForEach(board.columns) { column in
                BoardColumnView(column: column, pictures: pictures)
                    .frame(width: column.kind == .done ? 220 : 232)
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

    /// Cancelled: a 40 pt stub with its count until shown, then a column like Done.
    @ViewBuilder private func cancelled(_ board: Board, pictures: BoardCardContext) -> some View {
        if showsCancelled {
            BoardColumnView(column: board.cancelled, pictures: pictures) { showsCancelled = false }
                .frame(width: 220)
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
    var load: (UUID) async -> Void

    func state(of id: UUID) -> BoardPictureState { states[id] ?? .unknown }
}

/// One column: its header, then its cards top to bottom. Open, Done and Cancelled sit on the
/// sidebar tone with an eyebrow and a glyph; a tag column is a hairline around its tag chip.
struct BoardColumnView: View {
    let column: BoardColumn
    let pictures: BoardCardContext
    /// Folds Cancelled back behind its stub; nil on the other columns.
    var onHide: (() -> Void)? = nil
    @Environment(\.stillPicture) private var still

    /// The count beside a header's word and on the Cancelled stub: 11 pt regular.
    static let count = TextStyle(typeface: .text, size: 11, weight: 400)
    /// "OPEN", "DONE", "CANCELLED": 11 pt bold, tracked a little wider than the eyebrow is tall.
    static let word = TextStyle(typeface: .text, size: 11, weight: 700, tracking: 1.4, uppercase: true)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
            if !column.isFixed {
                RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line, lineWidth: 1)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(column.title)
    }

    private var cards: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(column.cards) { card in
                BoardCardView(card: card, picture: pictures.state(of: card.id), now: pictures.now) {
                    await pictures.load(card.id)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 7) {
            if let tag = column.tag {
                Text("#\(tag)")
                    .textStyle(TextStyle(typeface: .text, size: 12, weight: 600))
                    .foregroundStyle(Theme.leaf)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.leafSoft, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
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
