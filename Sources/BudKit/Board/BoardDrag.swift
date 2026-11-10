#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// A card in hand over a column, as a still picture sets it: the renderer has no pointer, so the
/// picture says which card is lifted and which column it hovers over.
struct BoardDrag: Equatable {
    var card: UUID
    var over: BoardColumn.Kind?
}

/// What a column shows of a drag: whether the card in hand hovers over it, and, in a still
/// picture, the card to draw lifted over it. A live drag draws the system's own preview.
struct BoardCardHover: Equatable {
    var targeted = false
    var lifted: BoardCard? = nil
}

struct StillBoardDragKey: EnvironmentKey {
    static let defaultValue: BoardDrag? = nil
}

extension EnvironmentValues {
    var stillBoardDrag: BoardDrag? {
        get { self[StillBoardDragKey.self] }
        set { self[StillBoardDragKey.self] = newValue }
    }
}

/// A card that can be dragged by its id, to a column (a `budDrop`) or to a place in the sidebar.
struct BoardDraggable: ViewModifier {
    @Environment(\.stillPicture) private var still
    let id: UUID

    func body(content: Content) -> some View {
        if still {
            content
        } else {
            content.draggable(id.uuidString)
        }
    }
}

extension View {
    /// Lets the card be dragged by its id.
    func boardDraggable(_ id: UUID) -> some View {
        modifier(BoardDraggable(id: id))
    }
}

/// "Drop to close it": the slot at the top of a column while a card hovers over it, a dashed
/// leaf line around the words.
struct BoardDropHint: View {
    let column: BoardColumn.Kind

    var body: some View {
        Text(BoardDrop.hint(on: column))
            .textStyle(TextStyle(typeface: .text, size: 12, weight: 600))
            .foregroundStyle(Theme.leaf)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Theme.leafSoft, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Theme.leafLine, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            )
            .accessibilityIdentifier("board-drop-hint")
    }
}
#endif
