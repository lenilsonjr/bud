#if canImport(SwiftUI)
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
                .font(.title2)
                .foregroundStyle(Theme.accent)
            Text("Everything")
                .font(.title3.weight(.semibold))
            Text("\(store.tree.children(of: rootID).count) threads")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("+ Enrich", action: onAdd)
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(Theme.accent)
        }
        .frame(width: Metrics.hub.width, height: Metrics.hub.height)
        .background(cardBackground(radius: 16))
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture(perform: onTap)
    }

    private func chip(_ bud: Bud) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if bud.isTodo {
                Button(action: onToggle) {
                    Image(systemName: bud.isDone ? "checkmark.square.fill" : "square")
                }
                .buttonStyle(.plain)
                .foregroundStyle(bud.isDone ? Theme.accent : .secondary)
            } else {
                Circle()
                    .fill(Theme.accent.opacity(0.6))
                    .frame(width: 6, height: 6)
                    .padding(.top, 6)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(bud.text)
                    .strikethrough(bud.isDone)
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                    .foregroundStyle(bud.isDone ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                Text(subtitle(bud))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button(action: onAdd) {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(width: Metrics.chip.width, height: Metrics.chip.height, alignment: .topLeading)
        .background(cardBackground(radius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture(perform: onTap)
    }

    private func subtitle(_ bud: Bud) -> String {
        let kids = store.tree.children(of: bud.id)
        if kids.isEmpty { return bud.isTodo ? (bud.isDone ? "Done" : "To-do") : "Note" }
        let open = store.tree.openCount(under: bud.id)
        return "\(kids.count) connected" + (open > 0 ? " · \(open) open" : "")
    }

    private func cardBackground(radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(Theme.card)
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .stroke(lit ? Theme.accent.opacity(0.9) : Theme.stroke, lineWidth: lit ? 1.5 : 1)
            )
            .shadow(color: Theme.accent.opacity(lit ? 0.45 : 0), radius: lit ? 18 : 0)
    }
}
#endif
