#if canImport(SwiftUI)
import SwiftUI

/// The colours of one card, by kind and by whether the light rests on it. Shared by the Mac
/// cards and the TV cards so the two never drift.
struct CardStyle {
    let fill: Color
    let line: Color
    let ink: Color
    let meta: Color

    /// A to-do or thread card is sage, a note pale olive, the lit card solid leaf with dark text.
    static func chip(for bud: Bud, lit: Bool) -> CardStyle {
        if lit {
            return CardStyle(fill: Theme.cardLit, line: Theme.cardLitLine, ink: Theme.cardLitInk, meta: Theme.cardLitMeta)
        }
        if bud.isTodo {
            return CardStyle(fill: Theme.card, line: Theme.cardLine, ink: Theme.cardInk, meta: Theme.cardMeta)
        }
        return CardStyle(fill: Theme.cardNote, line: Theme.cardNoteLine, ink: Theme.cardInk, meta: Theme.cardNoteMeta)
    }

    /// The hub is forest with the lavender leaf mark; lit, its line turns to the accent.
    static func hub(lit: Bool) -> CardStyle {
        CardStyle(fill: Theme.hub, line: lit ? Theme.hubAccent : Theme.hubLine, ink: Theme.hubInk, meta: Theme.hubMeta)
    }

    /// The caption under a title: what a bud holds, or what kind of leaf it is.
    static func caption(for bud: Bud, in tree: Tree) -> String {
        let kids = tree.children(of: bud.id)
        if kids.isEmpty { return bud.isTodo ? (bud.isDone ? "Done" : "To-do") : "Note" }
        let open = tree.openCount(under: bud.id)
        return "\(kids.count) connected" + (open > 0 ? " · \(open) open" : "")
    }
}

/// The lead glyph of a title row: a box for a to-do, a dot for a note.
struct KindMark: View {
    let bud: Bud
    let style: CardStyle

    var body: some View {
        if bud.isTodo {
            Image(systemName: bud.isDone ? "checkmark.square.fill" : "square")
                .foregroundStyle(bud.isDone ? Theme.leaf : style.meta)
        } else {
            Circle()
                .fill(Theme.leaf)
                .frame(width: 6, height: 6)
                .padding(.top, 6)
        }
    }
}
#endif
