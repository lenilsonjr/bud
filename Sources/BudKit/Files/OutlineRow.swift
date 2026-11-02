#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// One row of an outline: the disclosure that opens one more level in place, the box or the
/// dot, the title, "n inside" when it holds something, and the ⋯ that opens the bud menu. A
/// click on the title selects the bud. The row can be dragged onto any other row or onto a bud
/// in the sidebar, and takes a drop itself.
struct OutlineRow: View {
    let bud: Bud
    @ObservedObject var store: BudStore
    let depth: Int
    let expanded: Bool
    let onDisclose: () -> Void
    let onMove: () -> Void
    @Environment(\.stillPicture) private var still

    var body: some View {
        let kids = store.tree.children(of: bud.id).count
        HStack(alignment: .top, spacing: 8) {
            Group {
                if kids > 0 {
                    Button(action: onDisclose) {
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                            .textRole(.caption)
                            .foregroundStyle(Theme.text3)
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear.frame(width: 16, height: 16)
                }
            }
            .padding(.top, 2)
            if bud.isTodo {
                Button { store.tick(bud.id) } label: {
                    KindMark(bud: bud, style: CardStyle.chip(for: bud, lit: false))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            } else {
                KindMark(bud: bud, style: CardStyle.chip(for: bud, lit: false))
            }
            Button { store.center = bud.id } label: {
                Text(bud.text)
                    .textRole(.body)
                    .strikethrough(bud.isDone)
                    .foregroundStyle(bud.isDone ? Theme.text3 : Theme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if kids > 0 {
                Text(kids == 1 ? "1 inside" : "\(kids) inside")
                    .textRole(.caption)
                    .foregroundStyle(Theme.text2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.line, in: Capsule())
            }
            dots
        }
        .padding(.leading, CGFloat(depth) * 20)
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .overlay(alignment: .bottom) { Theme.line.frame(height: 1) }
        .contentShape(Rectangle())
        .budMenu(bud.id, store: store)
        .draggable(bud.id.uuidString)
        .budDrop { store.move($0, under: bud.id) }
    }

    /// The ⋯ opens the same menu as a long press. The picture renderer cannot draw a menu, so a
    /// still picture shows the glyph alone.
    @ViewBuilder private var dots: some View {
        if still {
            Image(systemName: "ellipsis")
                .textRole(.label)
                .foregroundStyle(Theme.text3)
                .frame(width: 20, height: 20)
        } else {
            Menu {
                BudMenuItems(id: bud.id, store: store, onMove: onMove)
            } label: {
                Image(systemName: "ellipsis")
                    .textRole(.label)
                    .foregroundStyle(Theme.text3)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }
}

/// A child as the document's Inside section lists it: the kind mark, the title, the caption.
struct PageRow: View {
    let bud: Bud
    let tree: Tree

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            KindMark(bud: bud, style: CardStyle.chip(for: bud, lit: false))
            Text(bud.text)
                .strikethrough(bud.isDone)
                .foregroundStyle(bud.isDone ? Theme.text3 : Theme.text)
            Spacer()
            Text(CardStyle.caption(for: bud, in: tree))
                .textRole(.caption)
                .foregroundStyle(Theme.text3)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }
}
#endif
