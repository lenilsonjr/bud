#if canImport(SwiftUI)
import SwiftUI

/// The one menu for a bud, the system's own: a long press on touch and TV, a right click or
/// control click on the Mac. Add inside…, Open, Open as file, Close or Reopen (Make a to-do for
/// a note), Move earlier and Move later where the surface shows every sibling (the canvas and the
/// TV row), Move to…, then Trash. The hub (Everything) has no menu.
///
/// Add inside… and Open take closures where the surface has its own way (the TV plants through
/// its own sheet, the canvas opens the card in place); without them Add inside… raises the quick
/// add modal for the bud and Open opens the bud as a file.
struct BudMenu: ViewModifier {
    let id: UUID
    @ObservedObject var store: BudStore
    var onAdd: (() -> Void)? = nil
    var onOpen: (() -> Void)? = nil
    /// Offers Move earlier and Move later: only where every sibling is on screen.
    var reorder = false

    #if !os(tvOS)
    @State private var moving: Bud? = nil
    #endif

    func body(content: Content) -> some View {
        if id == rootID {
            content
        } else {
            attach(content)
        }
    }

    #if os(tvOS)
    private func attach(_ content: Content) -> some View {
        content.contextMenu {
            if let onAdd { Button("Add inside…", systemImage: "plus", action: onAdd) }
            if let onOpen { Button("Open", systemImage: "arrow.up.left.and.arrow.down.right", action: onOpen) }
            stateItem
            if reorder { BudShiftItems(id: id, store: store) }
            Divider()
            trashItem
        }
    }
    #else
    private func attach(_ content: Content) -> some View {
        content
            .contextMenu {
                BudMenuItems(id: id, store: store, onAdd: onAdd, onOpen: onOpen, reorder: reorder, onMove: { moving = store.tree.bud(id) })
            }
            .sheet(item: $moving) { bud in MoveToPicker(store: store, bud: bud) }
    }
    #endif

    /// Close or Reopen for a to-do; Make a to-do for a note.
    @ViewBuilder private var stateItem: some View {
        BudStateItem(id: id, store: store)
    }

    private var trashItem: some View {
        Button("Trash", systemImage: "trash", role: .destructive) { store.trash(id) }
    }
}

/// Close or Reopen for a to-do; Make a to-do for a note.
struct BudStateItem: View {
    let id: UUID
    @ObservedObject var store: BudStore

    var body: some View {
        if let bud = store.tree.bud(id) {
            if bud.isTodo {
                Button(bud.isDone ? "Reopen" : "Close", systemImage: bud.isDone ? "circle" : "checkmark.circle") {
                    store.tick(id)
                }
            } else {
                Button("Make a to-do", systemImage: "checkmark.square") { store.makeTodo(id) }
            }
        }
    }
}

/// Move earlier and Move later: trade places with the sibling before or after, the reorder that
/// needs no drag (Reduce Motion, VoiceOver, the TV remote). Each shows only when there is one.
struct BudShiftItems: View {
    let id: UUID
    @ObservedObject var store: BudStore

    var body: some View {
        if store.tree.sibling(of: id, offset: -1) != nil {
            Button("Move earlier", systemImage: "arrow.uturn.backward") { store.shift(id, by: -1) }
        }
        if store.tree.sibling(of: id, offset: 1) != nil {
            Button("Move later", systemImage: "arrow.uturn.forward") { store.shift(id, by: 1) }
        }
    }
}

#if !os(tvOS)
/// The items of the bud menu, the same from a long press, a right click or a row's ⋯ button.
struct BudMenuItems: View {
    let id: UUID
    @ObservedObject var store: BudStore
    var onAdd: (() -> Void)? = nil
    var onOpen: (() -> Void)? = nil
    var reorder = false
    let onMove: () -> Void

    var body: some View {
        Button("Add inside…", systemImage: "plus") {
            if let onAdd { onAdd() } else { store.modal = .add(parent: id) }
        }
        Button("Open", systemImage: "arrow.up.left.and.arrow.down.right") {
            if let onOpen { onOpen() } else { store.openAsFile(id) }
        }
        if store.surface != .files {
            Button("Open as file", systemImage: "doc.text") { store.openAsFile(id) }
        }
        BudStateItem(id: id, store: store)
        if reorder { BudShiftItems(id: id, store: store) }
        Button("Move to…", systemImage: "arrow.turn.down.right", action: onMove)
        Divider()
        Button("Trash", systemImage: "trash", role: .destructive) { store.trash(id) }
    }
}
#endif

extension View {
    /// Attaches the bud menu for `id`. See `BudMenu`.
    func budMenu(_ id: UUID, store: BudStore, onAdd: (() -> Void)? = nil, onOpen: (() -> Void)? = nil, reorder: Bool = false) -> some View {
        modifier(BudMenu(id: id, store: store, onAdd: onAdd, onOpen: onOpen, reorder: reorder))
    }
}
#endif
