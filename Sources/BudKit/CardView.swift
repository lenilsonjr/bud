#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

struct CardView: View {
    let id: UUID
    @ObservedObject var store: BudStore
    let role: CardRole
    let lit: Bool
    /// 1 in the current orbit or under the light, 0.35 outside it.
    let light: Double
    let onTap: () -> Void
    let onOpen: () -> Void
    let onAdd: () -> Void
    let onToggle: () -> Void

    var body: some View {
        Group {
            if id == rootID {
                hub
            } else if let bud = store.tree.bud(id) {
                if store.layout.cards[id]?.hub == true {
                    threadHub(bud)
                } else {
                    chip(bud)
                }
            }
        }
        .animation(.easeOut(duration: 0.35), value: lit)
        .animation(.easeOut(duration: 0.35), value: light)
    }

    /// The fill takes the full dim as a wash toward the canvas, so the card stays opaque and no
    /// line shows through it; the words floor at 55% so a dimmed card still reads, and at 30%
    /// on a card a lens faded below any dim, so the lens's answers stand out.
    private var fillLight: Double { lit ? 1 : light }
    private var inkLight: Double { lit ? 1 : max(light, light < 0.35 ? 0.3 : 0.55) }

    private func wash(_ radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(Theme.canvas.opacity(1 - fillLight))
            .allowsHitTesting(false)
    }

    private var hub: some View {
        VStack(spacing: 6) {
            Image(systemName: "leaf.fill")
                .textRole(.heading)
                .foregroundStyle(Theme.hubMark)
                .accessibilityHidden(true)
            Text("Everything")
                .textRole(.title)
                .foregroundStyle(Theme.hubInk)
            Text("\(store.tree.children(of: rootID).count) threads")
                .textRole(.caption)
                .foregroundStyle(Theme.hubMeta)
            Button("Add", action: onAdd)
                .buttonStyle(.plain)
                .textRole(.label)
                .foregroundStyle(Theme.hubAccent)
        }
        .opacity(inkLight)
        .frame(width: Metrics.hub.width, height: Metrics.hub.height)
        .background(hubBackground.overlay(wash(Radius.hub)))
        .contentShape(RoundedRectangle(cornerRadius: Radius.hub))
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, onTap)
    }

    /// Inside a thread the thread is the hub (A2): its box in the corner when it is a to-do, the
    /// title in the display face, what it holds, and Enrich where Everything has Add.
    private func threadHub(_ bud: Bud) -> some View {
        let style = CardStyle.hub(lit: lit)
        return VStack(spacing: 6) {
            Text(bud.text)
                .textStyle(TextStyle(typeface: .display, size: 20, weight: 500))
                .strikethrough(bud.isDone)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(bud.isDone ? style.meta : style.ink)
            Text(CardStyle.caption(for: bud, in: store.tree))
                .textRole(.caption)
                .foregroundStyle(style.meta)
            Button("Enrich", action: onAdd)
                .buttonStyle(.plain)
                .textRole(.label)
                .foregroundStyle(Theme.hubAccent)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .frame(width: Metrics.hub.width, height: Metrics.hub.height)
        .overlay(alignment: .topLeading) {
            if bud.isTodo {
                Button(action: onToggle) { KindMark(bud: bud, style: style) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(bud.isDone ? "Reopen" : "Close")
                    .padding(12)
            }
        }
        .opacity(inkLight)
        .background(hubBackground.overlay(wash(Radius.hub)))
        .overlay(EntryRing(fresh: store.isFresh(id), radius: Radius.hub))
        .overlay(alignment: .topTrailing) { LinkBadge(count: store.links.into[id]?.count ?? 0, lit: lit) }
        .contentShape(RoundedRectangle(cornerRadius: Radius.hub))
        .onTapGesture(perform: onTap)
        // One VoiceOver element per card: the tick and the + come along as its actions, and the
        // moves land once, on the card.
        .accessibilityElement(children: .combine)
        .accessibilityValue(spokenValue(done: bud.isDone, match: store.canvasLight[id], lensOn: store.canvasLens != nil))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, onTap)
        .budMenu(id, store: store, onAdd: onAdd, onOpen: onOpen, reorder: true)
    }

    private func chip(_ bud: Bud) -> some View {
        HStack(alignment: .top, spacing: 8) {
            let style = CardStyle.chip(for: bud, lit: lit)
            if bud.isTodo {
                Button(action: onToggle) { KindMark(bud: bud, style: style) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(bud.isDone ? "Reopen" : "Close")
            } else {
                KindMark(bud: bud, style: style)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(bud.text)
                    .strikethrough(bud.isDone)
                    .textRole(.cardTitle)
                    .lineLimit(2)
                    .foregroundStyle(bud.isDone ? style.meta : style.ink)
                if let from = bud.from {
                    SourceRow(from: from, mark: store.mark(of: bud), fallback: style.meta)
                } else {
                    Text(CardStyle.caption(for: bud, in: store.tree))
                        .textRole(.caption)
                        .foregroundStyle(style.meta)
                }
            }
            Spacer(minLength: 0)
            Button(action: onAdd) {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .textRole(.label)
            .foregroundStyle(lit ? style.meta : Theme.text2)
            .help("Add inside")
            .accessibilityLabel("Add inside")
        }
        .padding(10)
        .frame(width: Metrics.chip.width, height: Metrics.chip.height, alignment: .topLeading)
        .opacity(inkLight)
        .background(chipBackground(bud).overlay(wash(Radius.card)))
        .overlay(EntryRing(fresh: store.isFresh(id), radius: Radius.card))
        .overlay(alignment: .topTrailing) { LinkBadge(count: store.links.into[id]?.count ?? 0, lit: lit) }
        .contentShape(RoundedRectangle(cornerRadius: Radius.card))
        .onTapGesture(perform: onTap)
        // One VoiceOver element per card: the tick and the + come along as its actions, and the
        // moves land once, on the card.
        .accessibilityElement(children: .combine)
        .accessibilityValue(spokenValue(done: bud.isDone, match: store.canvasLight[id], lensOn: store.canvasLens != nil))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, onTap)
        .budMenu(id, store: store, onAdd: onAdd, onOpen: onOpen, reorder: true)
    }

    private func chipBackground(_ bud: Bud) -> some View {
        let style = CardStyle.chip(for: bud, lit: lit)
        return RoundedRectangle(cornerRadius: Radius.card)
            .fill(style.fill)
            .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(style.line, lineWidth: lit ? 1.5 : 1))
            .shadow(color: lit ? Theme.glow : Theme.shadow, radius: lit ? 18 : 2, y: lit ? 0 : 2)
    }

    /// The entry cue: a leaf ring at 60% on a card that just joined the orbit, fading out over
    /// the cue's length with no bounce. A still picture keeps it at full.
    private struct EntryRing: View {
        let fresh: Bool
        let radius: CGFloat
        @State private var shown = 1.0
        @Environment(\.stillPicture) private var still

        var body: some View {
            if fresh {
                RoundedRectangle(cornerRadius: radius)
                    .stroke(Theme.leaf.opacity(0.6), lineWidth: 2)
                    .padding(-3)
                    .opacity(shown)
                    .allowsHitTesting(false)
                    .onAppear {
                        guard !still else { return }
                        withAnimation(.easeOut(duration: BudStore.entryCue)) { shown = 0 }
                    }
            }
        }
    }

    /// How many buds link to the card, on its corner: nothing while none do.
    private struct LinkBadge: View {
        let count: Int
        let lit: Bool

        var body: some View {
            if count > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "link")
                    Text("\(count)")
                }
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(lit ? Theme.onLeaf : Theme.leaf)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(lit ? Theme.leaf : Theme.raised, in: Capsule())
                .overlay(Capsule().stroke(lit ? Theme.leaf : Theme.line, lineWidth: 1))
                .offset(x: -8, y: -8)
                .allowsHitTesting(false)
                // One phrase for the glyph and the number, so the card says it once.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(count == 1 ? "1 bud links here" : "\(count) buds link here")
            }
        }
    }

    private var hubBackground: some View {
        let style = CardStyle.hub(lit: lit)
        return RoundedRectangle(cornerRadius: Radius.hub)
            .fill(style.fill)
            .overlay(RoundedRectangle(cornerRadius: Radius.hub).stroke(style.line, lineWidth: lit ? 1.5 : 1))
            .shadow(color: lit ? Theme.glow : Theme.shadowStrong, radius: lit ? 18 : 10, y: lit ? 0 : 4)
    }
}
#endif
