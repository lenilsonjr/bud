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

/// A column as a drop target for a card dragged by its id: says while one hovers, and hands over
/// the id when it lands. The picture renderer cannot draw a drop destination, so it is left off
/// in a still picture.
struct BoardDropTarget: ViewModifier {
    @Environment(\.stillPicture) private var still
    let onTarget: (Bool) -> Void
    let onDrop: (UUID) -> Bool

    func body(content: Content) -> some View {
        if still {
            content
        } else {
            content.dropDestination(for: String.self) { items, _ in
                guard let id = items.first.flatMap(UUID.init(uuidString:)) else { return false }
                return onDrop(id)
            } isTargeted: { onTarget($0) }
        }
    }
}

/// A card that can be dragged by its id, to a column or to a place in the sidebar.
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
    /// Accepts a dragged card: `onTarget` while one hovers, `onDrop` with its id when it lands.
    func boardDrop(onTarget: @escaping (Bool) -> Void, onDrop: @escaping (UUID) -> Bool) -> some View {
        modifier(BoardDropTarget(onTarget: onTarget, onDrop: onDrop))
    }

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
