#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

struct CardView: View {
    let id: UUID
    @ObservedObject var store: BudStore
    let role: CardRole
    let lit: Bool
    let onTap: () -> Void
    let onOpen: () -> Void
    let onAdd: () -> Void
    let onToggle: () -> Void

    var body: some View {
        Group {
            if id == rootID {
                hub
            } else if let bud = store.tree.bud(id) {
                chip(bud)
            }
        }
        .opacity(lit ? 1 : Theme.light(for: role))
        .animation(.easeOut(duration: 0.35), value: lit)
    }

    private var hub: some View {
        VStack(spacing: 6) {
            Image(systemName: "leaf.fill")
                .textRole(.heading)
                .foregroundStyle(Theme.hubMark)
            Text("Everything")
                .textRole(.title)
                .foregroundStyle(Theme.hubInk)
            Text("\(store.tree.children(of: rootID).count) threads")
                .textRole(.caption)
                .foregroundStyle(Theme.hubMeta)
            Button("+ Enrich", action: onAdd)
                .buttonStyle(.plain)
                .textRole(.label)
                .foregroundStyle(Theme.hubAccent)
        }
        .frame(width: Metrics.hub.width, height: Metrics.hub.height)
        .background(hubBackground)
        .contentShape(RoundedRectangle(cornerRadius: Radius.xl))
        .onTapGesture(perform: onTap)
    }

    private func chip(_ bud: Bud) -> some View {
        HStack(alignment: .top, spacing: 8) {
            let style = CardStyle.chip(for: bud, lit: lit)
            if bud.isTodo {
                Button(action: onToggle) { KindMark(bud: bud, style: style) }
                    .buttonStyle(.plain)
            } else {
                KindMark(bud: bud, style: style)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(bud.text)
                    .strikethrough(bud.isDone)
                    .textRole(.cardTitle)
                    .lineLimit(2)
                    .foregroundStyle(bud.isDone ? style.meta : style.ink)
                Text(CardStyle.caption(for: bud, in: store.tree))
                    .textRole(.caption)
                    .foregroundStyle(style.meta)
            }
            Spacer(minLength: 0)
            Button(action: onAdd) {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .textRole(.label)
            .foregroundStyle(style.meta)
        }
        .padding(10)
        .frame(width: Metrics.chip.width, height: Metrics.chip.height, alignment: .topLeading)
        .background(chipBackground(bud))
        .contentShape(RoundedRectangle(cornerRadius: Radius.md))
        .onTapGesture(perform: onTap)
        .onLongPressGesture(minimumDuration: 0.4, perform: onOpen)
    }

    private func chipBackground(_ bud: Bud) -> some View {
        let style = CardStyle.chip(for: bud, lit: lit)
        return RoundedRectangle(cornerRadius: Radius.md)
            .fill(style.fill)
            .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(style.line, lineWidth: lit ? 1.5 : 1))
            .shadow(color: lit ? Theme.glow : Theme.shadow, radius: lit ? 18 : 2, y: lit ? 0 : 2)
    }

    private var hubBackground: some View {
        let style = CardStyle.hub(lit: lit)
        return RoundedRectangle(cornerRadius: Radius.xl)
            .fill(style.fill)
            .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(style.line, lineWidth: lit ? 1.5 : 1))
            .shadow(color: lit ? Theme.glow : Theme.shadowStrong, radius: lit ? 18 : 10, y: lit ? 0 : 4)
    }
}
#endif
