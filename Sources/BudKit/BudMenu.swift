#if canImport(SwiftUI)
import SwiftUI

/// The one menu for a bud, the system's own: a long press on touch and TV, a right click or
/// control click on the Mac. Add inside…, Open, Open as file, Close or Reopen (Make a to-do for
/// a note), Move to…, then Trash. The hub (Everything) has no menu.
///
/// Add inside… and Open take closures where the surface has its own way (the canvas plants
/// through its sheet and opens the card in place); without them the menu presents the quick add
/// sheet itself and Open opens the bud as a file.
struct BudMenu: ViewModifier {
    let id: UUID
    @ObservedObject var store: BudStore
    var onAdd: (() -> Void)? = nil
    var onOpen: (() -> Void)? = nil

    #if !os(tvOS)
    @State private var adding: AddTarget? = nil
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
            Divider()
            trashItem
        }
    }
    #else
    private func attach(_ content: Content) -> some View {
        content
            .contextMenu {
                Button("Add inside…", systemImage: "plus") {
                    if let onAdd { onAdd() } else { adding = AddTarget(parent: id) }
                }
                Button("Open", systemImage: "arrow.up.left.and.arrow.down.right") {
                    if let onOpen { onOpen() } else { store.openAsFile(id) }
                }
                if store.surface != .files {
                    Button("Open as file", systemImage: "doc.text") { store.openAsFile(id) }
                }
                stateItem
                Button("Move to…", systemImage: "arrow.turn.down.right") { moving = store.tree.bud(id) }
                Divider()
                trashItem
            }
            .sheet(item: $adding) { target in AddSheet(store: store, mode: target.mode) }
            .sheet(item: $moving) { bud in MoveToPicker(store: store, bud: bud) }
    }
    #endif

    /// Close or Reopen for a to-do; Make a to-do for a note.
    @ViewBuilder private var stateItem: some View {
        if let bud = store.tree.bud(id) {
            if bud.isTodo {
                Button(bud.isDone ? "Reopen" : "Close", systemImage: bud.isDone ? "circle" : "checkmark.circle") {
                    store.toggle(id)
                }
            } else {
                Button("Make a to-do", systemImage: "checkmark.square") { store.makeTodo(id) }
            }
        }
    }

    private var trashItem: some View {
        Button("Trash", systemImage: "trash", role: .destructive) { store.trash(id) }
    }
}

extension View {
    /// Attaches the bud menu for `id`. See `BudMenu`.
    func budMenu(_ id: UUID, store: BudStore, onAdd: (() -> Void)? = nil, onOpen: (() -> Void)? = nil) -> some View {
        modifier(BudMenu(id: id, store: store, onAdd: onAdd, onOpen: onOpen))
    }
}
#endif
