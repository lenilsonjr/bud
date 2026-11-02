#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

struct CardView: View {
    let id: UUID
    @ObservedObject var store: BudStore
    let role: CardRole
    let lit: Bool
    let onTap: () -> Void
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
            Image(systemName: "circle.hexagongrid")
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
            if bud.isTodo {
                Button(action: onToggle) {
                    Image(systemName: bud.isDone ? "checkmark.square.fill" : "square")
                }
                .buttonStyle(.plain)
                .foregroundStyle(bud.isDone ? Theme.leaf : meta(bud))
            } else {
                Circle()
                    .fill(Theme.leaf)
                    .frame(width: 6, height: 6)
                    .padding(.top, 6)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(bud.text)
                    .strikethrough(bud.isDone)
                    .textRole(.cardTitle)
                    .lineLimit(2)
                    .foregroundStyle(bud.isDone ? meta(bud) : ink(bud))
                Text(subtitle(bud))
                    .textRole(.caption)
                    .foregroundStyle(meta(bud))
            }
            Spacer(minLength: 0)
            Button(action: onAdd) {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .textRole(.label)
            .foregroundStyle(meta(bud))
        }
        .padding(10)
        .frame(width: Metrics.chip.width, height: Metrics.chip.height, alignment: .topLeading)
        .background(chipBackground(bud))
        .contentShape(RoundedRectangle(cornerRadius: Radius.md))
        .onTapGesture(perform: onTap)
    }

    private func subtitle(_ bud: Bud) -> String {
        let kids = store.tree.children(of: bud.id)
        if kids.isEmpty { return bud.isTodo ? (bud.isDone ? "Done" : "To-do") : "Note" }
        let open = store.tree.openCount(under: bud.id)
        return "\(kids.count) connected" + (open > 0 ? " · \(open) open" : "")
    }

    // MARK: colours by kind and light

    private func ink(_ bud: Bud) -> Color { lit ? Theme.cardLitInk : Theme.cardInk }

    private func meta(_ bud: Bud) -> Color {
        lit ? Theme.cardLitMeta : (bud.isTodo ? Theme.cardMeta : Theme.cardNoteMeta)
    }

    private func fill(_ bud: Bud) -> Color {
        lit ? Theme.cardLit : (bud.isTodo ? Theme.card : Theme.cardNote)
    }

    private func line(_ bud: Bud) -> Color {
        lit ? Theme.cardLitLine : (bud.isTodo ? Theme.cardLine : Theme.cardNoteLine)
    }

    private func chipBackground(_ bud: Bud) -> some View {
        RoundedRectangle(cornerRadius: Radius.md)
            .fill(fill(bud))
            .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(line(bud), lineWidth: lit ? 1.5 : 1))
            .shadow(color: lit ? Theme.glow : Theme.shadow, radius: lit ? 18 : 6, y: lit ? 0 : 2)
    }

    private var hubBackground: some View {
        RoundedRectangle(cornerRadius: Radius.xl)
            .fill(Theme.hub)
            .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(lit ? Theme.hubAccent : Theme.hubLine, lineWidth: lit ? 1.5 : 1))
            .shadow(color: lit ? Theme.glow : Theme.shadowStrong, radius: lit ? 18 : 10, y: lit ? 0 : 4)
    }
}
#endif
