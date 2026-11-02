#if canImport(SwiftUI) && os(tvOS)
import SwiftUI

/// Bud on Apple TV: the same orbit canvas, driven by the remote. Swiping moves the focus from
/// card to card, the light rests on the focused one, a click centers a bud with children or
/// ticks a to-do, Menu steps out, Play/Pause ticks the to-do in focus. Capture is one line.
public struct BudTVView: View {
    @StateObject private var store: BudStore
    @State private var capturing = false

    @MainActor public init(fileURL: URL? = BudStore.defaultFile) {
        _store = StateObject(wrappedValue: BudStore(fileURL: fileURL))
    }

    public var body: some View {
        TVCanvas(store: store)
            .overlay(alignment: .top) { trail }
            .overlay(alignment: .bottom) { hint }
            .background(Theme.window)
            .textRole(.body)
            .foregroundStyle(Theme.text)
            .sheet(isPresented: $capturing) { TVCaptureSheet(store: store, parent: store.center) }
    }

    private var trail: some View {
        HStack(spacing: 14) {
            ForEach(Array(store.centerTrail.enumerated()), id: \.offset) { index, id in
                if index > 0 {
                    Text("›").foregroundStyle(Theme.text3)
                }
                Text(store.tree.title(of: id))
                    .textRole(index == store.centerTrail.count - 1 ? .heading : .label)
                    .foregroundStyle(index == store.centerTrail.count - 1 ? Theme.leaf : Theme.text2)
            }
            Spacer(minLength: 24)
            Button {
                capturing = true
            } label: {
                Label("Capture", systemImage: "plus")
            }
            .textRole(.label)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .background(Theme.glass, in: RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(Theme.line, lineWidth: 1))
        .padding(.horizontal, 60)
        .padding(.top, 40)
    }

    private var hint: some View {
        Text("Swipe to move the light · click a bud with children to go in · click or Play/Pause ticks a to-do · Menu steps out · what you plant here stays on this TV until sync arrives")
            .textRole(.caption)
            .foregroundStyle(Theme.text3)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Theme.glass, in: Capsule())
            .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
            .padding(.bottom, 40)
    }
}

/// The orbit canvas for the focus engine: every card is a button placed by the shared layout,
/// so a swipe on the remote lands on the nearest card in that direction. The camera sits on the
/// center and only slides when the focus wanders out of view.
struct TVCanvas: View {
    @ObservedObject var store: BudStore
    @State private var camera: CGPoint = .zero
    @FocusState private var focused: UUID?

    private let scale: CGFloat = 1.6
    private let margin: CGFloat = 140

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let layout = store.layout
            let lifted = focused.map { store.tree.orbit(of: $0) } ?? []
            ZStack {
                Theme.canvas
                EdgesLayer(layout: layout, scale: scale) { screenPoint($0, in: size) }
                ForEach(layout.order, id: \.self) { id in
                    if let placed = layout.cards[id] {
                        Button {
                            tap(id)
                        } label: {
                            TVCardFace(id: id, store: store, lit: focused == id)
                        }
                        .buttonStyle(.plain)
                        .focused($focused, equals: id)
                        .opacity(focused == id ? 1 : lightLevel(role: placed.role, lifted: lifted.contains(id)))
                        .scaleEffect(scale * (focused == id ? 1.08 : 1))
                        .position(screenPoint(placed.position, in: size))
                        .zIndex(focused == id ? 2 : (placed.role == .center ? 1 : 0))
                        .animation(.easeOut(duration: 0.25), value: focused)
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            .onChange(of: focused) { _, id in keep(id, visible: size) }
            .onChange(of: store.center) { _, id in
                withAnimation(.spring(duration: 0.8, bounce: 0.12)) { camera = .zero }
                focused = id
            }
            .onAppear { focused = store.center }
        }
        .onExitCommand { stepOut() }
        .onPlayPauseCommand { toggleFocused() }
    }

    private func screenPoint(_ p: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2 + (p.x - camera.x) * scale, y: size.height / 2 + (p.y - camera.y) * scale)
    }

    /// Slides the camera just enough that the focused card sits inside the viewport.
    private func keep(_ id: UUID?, visible size: CGSize) {
        guard let id, let placed = store.layout.cards[id] else { return }
        let s = Metrics.size(of: id)
        let half = CGSize(width: s.width / 2 * scale, height: s.height / 2 * scale)
        let p = screenPoint(placed.position, in: size)
        var dx: CGFloat = 0, dy: CGFloat = 0
        if p.x - half.width < margin { dx = (p.x - half.width - margin) / scale }
        if p.x + half.width > size.width - margin { dx = (p.x + half.width - size.width + margin) / scale }
        if p.y - half.height < margin { dy = (p.y - half.height - margin) / scale }
        if p.y + half.height > size.height - margin { dy = (p.y + half.height - size.height + margin) / scale }
        guard dx != 0 || dy != 0 else { return }
        withAnimation(.spring(duration: 0.6, bounce: 0)) {
            camera.x += dx
            camera.y += dy
        }
    }

    private func tap(_ id: UUID) {
        if id == rootID || store.tree.hasChildren(id) {
            guard id != store.center else { return }
            withAnimation(.spring(duration: 0.8, bounce: 0.12)) { store.center = id }
        } else if store.tree.bud(id)?.isTodo == true {
            store.toggle(id)
        }
    }

    private func toggleFocused() {
        guard let id = focused, store.tree.bud(id)?.isTodo == true else { return }
        store.toggle(id)
    }

    private func stepOut() {
        guard store.center != rootID else { return }
        withAnimation(.spring(duration: 0.8, bounce: 0.12)) { store.back() }
    }
}

/// The face of a card: the hub for Everything, a chip for a bud. No buttons inside, so the
/// whole face is one focus target for the remote.
struct TVCardFace: View {
    let id: UUID
    @ObservedObject var store: BudStore
    let lit: Bool

    var body: some View {
        if id == rootID {
            hub
        } else if let bud = store.tree.bud(id) {
            chip(bud)
        }
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
        }
        .frame(width: Metrics.hub.width, height: Metrics.hub.height)
        .background(
            RoundedRectangle(cornerRadius: Radius.xl)
                .fill(CardStyle.hub(lit: lit).fill)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(CardStyle.hub(lit: lit).line, lineWidth: lit ? 1.5 : 1))
                .shadow(color: lit ? Theme.glow : Theme.shadowStrong, radius: lit ? 18 : 10, y: lit ? 0 : 4)
        )
    }

    private func chip(_ bud: Bud) -> some View {
        let style = CardStyle.chip(for: bud, lit: lit)
        return HStack(alignment: .top, spacing: 8) {
            KindMark(bud: bud, style: style)
            VStack(alignment: .leading, spacing: 3) {
                Text(bud.text)
                    .strikethrough(bud.isDone)
                    .textRole(.cardTitle)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(bud.isDone ? style.meta : style.ink)
                Text(CardStyle.caption(for: bud, in: store.tree))
                    .textRole(.caption)
                    .foregroundStyle(style.meta)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: Metrics.chip.width, height: Metrics.chip.height, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md)
                .fill(style.fill)
                .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(style.line, lineWidth: lit ? 1.5 : 1))
                .shadow(color: lit ? Theme.glow : Theme.shadow, radius: lit ? 18 : 2, y: lit ? 0 : 2)
        )
    }
}

/// One line of text from the TV keyboard or dictation, planted under the current bud.
struct TVCaptureSheet: View {
    @ObservedObject var store: BudStore
    let parent: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var todo = true

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            Text("New bud under \(store.tree.title(of: parent))")
                .textRole(.title)
                .foregroundStyle(Theme.text)
            TextField("What is it?", text: $text)
                .onSubmit(plant)
            Picker("Kind", selection: $todo) {
                Text("To-do").tag(true)
                Text("Note").tag(false)
            }
            .pickerStyle(.segmented)
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Plant", action: plant)
                    .disabled(trimmed.isEmpty)
            }
            .textRole(.label)
        }
        .padding(80)
        .textRole(.body)
        .foregroundStyle(Theme.text)
        .background(Theme.surface)
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func plant() {
        guard !trimmed.isEmpty else { return }
        store.add(trimmed, todo: todo, under: parent)
        dismiss()
    }
}
#endif
