#if canImport(SwiftUI) && os(tvOS)
import SwiftUI

/// The tabs of the TV: the orbit canvas, Files, and Settings, which Devices grew into as G16
/// allows.
enum TVTab: String, CaseIterable, Hashable {
    case canvas = "Canvas"
    case files = "Files"
    case settings = "Settings"
}

/// Bud on Apple TV: the same orbit canvas, driven by the remote. Swiping moves the focus from
/// card to card, the light rests on the focused one, a click centers a bud with children or
/// ticks a to-do, Menu steps out, Play/Pause ticks the to-do in focus. Capture is one line. A
/// glass pill at the top switches to Files, the pages the Mac sidebar has, and to Settings, where
/// the TV picks its appearance, starts over, pairs the next device or joins a vault; the
/// magnifier beside the tabs goes anywhere by typing.
public struct BudTVView: View {
    @StateObject private var store: BudStore

    @MainActor public init(fileURL: URL? = BudStore.defaultFile) {
        _store = StateObject(wrappedValue: BudStore(fileURL: fileURL))
    }

    /// A store the caller already holds: the app's, over the vault on disk.
    @MainActor public init(store: BudStore) {
        _store = StateObject(wrappedValue: store)
    }

    public var body: some View {
        TVShell(store: store)
    }
}

private extension TVForeground.Phase {
    init(_ phase: ScenePhase) {
        switch phase {
        case .active: self = .active
        case .background: self = .background
        default: self = .inactive
        }
    }
}

/// The window's contents, watching both the store and its devices so the join and the first
/// fetch can move the screen along.
struct TVShell: View {
    @ObservedObject var store: BudStore
    @ObservedObject var devices: DeviceStore
    @State private var capturing = false
    @State private var tab: TVTab = .canvas
    @State private var joining = false
    @State private var fetching = false
    @State private var reading: TVAddTarget? = nil
    @State private var searching = false
    @ObservedObject private var flags = Flags.shared
    @FocusState private var focusedTab: TVTab?
    @FocusState private var searchLit: Bool
    @Environment(\.scenePhase) private var scenePhase
    /// Whether the app went to the background since it was last active.
    @State private var foreground = TVForeground()

    init(store: BudStore) {
        self.store = store
        self.devices = store.devices
    }

    var body: some View {
        if let fetch = devices.launchFetch {
            // The cache was cleared: no card shows until the vault is back from the peers. Menu
            // stops waiting, for a peer that is not around.
            TVFetchScreen(text: TVDevicesText.launchFetchBody, received: fetch.received, total: fetch.total)
                // Focusable, so Menu reaches it rather than leaving the app.
                .focusable()
                .onExitCommand { devices.endLaunchFetch() }
                .preferredColorScheme(flags.appearance.colorScheme)
                .onChange(of: scenePhase) { _, phase in sceneMoved(to: phase, syncing: false) }
        } else {
            shell
        }
    }

    private var shell: some View {
        VStack(spacing: 0) {
            tabs
            switch tab {
            case .canvas:
                TVCanvas(store: store, onOpen: open)
                    .ignoresSafeArea()
                    .overlay(alignment: .top) { trail }
            case .files:
                TVFilesTab(store: store, covered: reading != nil, onLeave: { tab = .canvas }, onOpen: open)
            case .settings:
                TVSettingsTab(store: store, devices: devices, flags: flags, onJoin: { joining = true }, onStartOver: startOver)
                    // Menu steps out, as on the canvas: back to Canvas rather than out of the app.
                    .onExitCommand { tab = .canvas }
            }
        }
        .background(Theme.window.ignoresSafeArea())
        .textRole(.body)
        .foregroundStyle(Theme.text)
        .sheet(isPresented: $capturing) { TVCaptureSheet(store: store, target: .inbox) }
        .fullScreenCover(isPresented: $joining) { TVJoinModal(devices: devices, close: { joining = false }) }
        .fullScreenCover(isPresented: $fetching) { fetchScreen }
        .fullScreenCover(item: $reading) { target in TVReadScreen(store: store, start: target.id, close: { reading = nil }) }
        .fullScreenCover(isPresented: $searching) { TVSearchScreen(store: store, close: { searching = false }) }
        .preferredColorScheme(flags.appearance.colorScheme)
        .task { await devices.start() }
        .onChange(of: devices.joinPhase) { _, phase in
            guard case let .joined(_, received, total) = phase else { return }
            joining = false
            if TVDevicesText.fetchIsDone(received: received, total: total) { finishFetch() } else { fetching = true }
        }
        .onChange(of: devices.lastSummary) { _, _ in
            // The first sync finished before the fetch reported a total: the cards can open.
            if fetching { finishFetch() }
        }
        .onChange(of: scenePhase) { _, phase in sceneMoved(to: phase, syncing: true) }
    }

    /// The node runs while the app is up; back from the background it syncs at once, with
    /// `syncing`, rather than on its next round, so the TV carries what one peer left for
    /// another. A system overlay that only made the app inactive asks for nothing. Into the
    /// background the kept pairing is brought up to date, in case the app is not back before the
    /// cache is cleared. The launch fetch notes the phases too, and leaves the syncing to the
    /// launch.
    private func sceneMoved(to phase: ScenePhase, syncing: Bool) {
        if foreground.moved(to: TVForeground.Phase(phase)), syncing { Task { await devices.syncNow() } }
        if phase == .background { devices.pairingMayHaveChanged() }
    }

    /// G18 while the vault comes over; the cards open on their own when it is done.
    @ViewBuilder private var fetchScreen: some View {
        if case let .joined(device, received, total) = devices.joinPhase {
            TVFetchScreen(text: TVDevicesText.fetchBody(from: device), received: received, total: total)
        } else {
            Theme.window.ignoresSafeArea()
        }
    }

    /// Open, from a menu or a leaf in Files: the bud is read full screen.
    private func open(_ id: UUID) {
        reading = TVAddTarget(id: id)
    }

    /// After Erase: the canvas, with the Canvas pill lit, so the new vault is what the viewer sees.
    private func startOver() {
        tab = .canvas
        focusedTab = .canvas
    }

    private func finishFetch() {
        fetching = false
        devices.resetJoin()
        tab = .canvas
    }

    /// The glass pill of tabs, the magnifier at its end: the focused one glows amethyst, the
    /// chosen tab reads in full ink.
    private var tabs: some View {
        HStack(spacing: 8) {
            ForEach(TVTab.allCases, id: \.self) { item in
                let shape = RoundedRectangle(cornerRadius: 32, style: .continuous)
                let lit = focusedTab == item
                Button { tab = item } label: {
                    Text(item.rawValue)
                        .font(Theme.font(TextStyle(typeface: .text, size: 29, weight: tab == item ? 600 : 500)))
                        .foregroundStyle(tab == item ? Theme.text : Theme.text2)
                        .padding(.horizontal, 34)
                        .padding(.vertical, 14)
                        .background(lit || tab == item ? Theme.amethystSoft : .clear, in: shape)
                        .overlay(shape.stroke(lit ? Theme.amethyst : .clear, lineWidth: 2))
                }
                .buttonStyle(.tvBare)
                .focused($focusedTab, equals: item)
            }
            let shape = RoundedRectangle(cornerRadius: 32, style: .continuous)
            Button { searching = true } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(Theme.text2)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(searchLit ? Theme.amethystSoft : .clear, in: shape)
                    .overlay(shape.stroke(searchLit ? Theme.amethyst : .clear, lineWidth: 2))
            }
            .buttonStyle(.tvBare)
            .focused($searchLit)
            .accessibilityLabel(TVSearchText.title)
        }
        .padding(8)
        .background(Theme.glass, in: RoundedRectangle(cornerRadius: 40, style: .continuous))
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        // The whole header is one section, so Up reaches the pill from any column below it.
        .focusSection()
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

}

/// The orbit canvas for the focus engine: every card is a button placed by the shared layout,
/// so a swipe on the remote lands on the nearest card in that direction. The camera sits on the
/// center and only slides when the focus wanders out of view.
struct TVCanvas: View {
    @ObservedObject var store: BudStore
    let onOpen: (UUID) -> Void
    @State private var camera: CGPoint = .zero
    @State private var adding: TVAddTarget? = nil
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
                EdgesLayer(layout: layout, scale: scale, lifted: Set(lifted)) { screenPoint($0, in: size) }
                ForEach(layout.order, id: \.self) { id in
                    if let placed = layout.cards[id] {
                        Button {
                            tap(id)
                        } label: {
                            TVCardFace(id: id, store: store, lit: focused == id)
                        }
                        .buttonStyle(.tvBare)
                        .budMenu(id, store: store, onAdd: { adding = TVAddTarget(id: id) }, onOpen: { onOpen(id) }, reorder: true)
                        .focused($focused, equals: id)
                        .opacity(focused == id ? 1 : lightLevel(role: placed.role, lifted: lifted.contains(id)))
                        .scaleEffect(scale * (focused == id ? 1.06 : 1))
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
        .sheet(item: $adding) { target in TVCaptureSheet(store: store, parent: target.id) }
        .onExitCommand { stepOut() }
        .onPlayPauseCommand { toggleFocused() }
    }

    private func screenPoint(_ p: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2 + (p.x - camera.x) * scale, y: size.height / 2 + (p.y - camera.y) * scale)
    }

    /// Slides the camera just enough that the focused card sits inside the viewport.
    private func keep(_ id: UUID?, visible size: CGSize) {
        guard let id, let placed = store.layout.cards[id] else { return }
        let s = Metrics.size(hub: placed.hub)
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
            store.tvTick(id)
        }
    }

    private func toggleFocused() {
        guard let id = focused else { return }
        store.tvTick(id)
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
            hub(Image(systemName: "leaf.fill"), title: "Everything", caption: "\(store.tree.children(of: rootID).count) threads")
        } else if let bud = store.tree.bud(id) {
            if store.layout.cards[id]?.hub == true {
                hub(KindMark(bud: bud, style: CardStyle.hub(lit: lit)), title: bud.text, caption: CardStyle.caption(for: bud, in: store.tree))
            } else {
                chip(bud)
            }
        }
    }

    /// The hub face: Everything with the leaf mark, or the centered thread with its own mark.
    private func hub(_ mark: some View, title: String, caption: String) -> some View {
        VStack(spacing: 6) {
            mark
                .textRole(.heading)
                .foregroundStyle(Theme.hubMark)
            Text(title)
                .textStyle(TextStyle(typeface: .display, size: 20, weight: 500))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.hubInk)
            Text(caption)
                .textRole(.caption)
                .foregroundStyle(Theme.hubMeta)
        }
        .padding(.horizontal, 12)
        .frame(width: Metrics.hub.width, height: Metrics.hub.height)
        .background(
            RoundedRectangle(cornerRadius: Radius.xl)
                .fill(CardStyle.hub(lit: lit).fill)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(CardStyle.hub(lit: lit).line, lineWidth: 1))
                .shadow(color: lit ? Theme.amethyst.opacity(0.55) : Theme.shadowStrong, radius: lit ? 28 : 10, y: lit ? 0 : 4)
        )
        .overlay { focusRing(radius: Radius.xl) }
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
                .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(style.line, lineWidth: 1))
                .shadow(color: lit ? Theme.amethyst.opacity(0.55) : Theme.shadow, radius: lit ? 28 : 2, y: lit ? 0 : 2)
        )
        .overlay { focusRing(radius: Radius.md) }
    }

    /// The focus stroke: 2 pt of amethyst at 60%, drawn only while the card is in focus.
    @ViewBuilder private func focusRing(radius: CGFloat) -> some View {
        if lit {
            RoundedRectangle(cornerRadius: radius).stroke(Theme.amethyst.opacity(0.6), lineWidth: 2)
        }
    }
}

extension BudStore {
    /// A tick from the remote: a done to-do reopens, an open one closes on its own, never the
    /// branch under it. The TV has no Close branch dialog to ask with, so it takes the quiet
    /// choice the Mac's dialog defaults to; the Undo lives in the toast where a host shows one.
    func tvTick(_ id: UUID) {
        guard let bud = tree.bud(id), bud.isTodo else { return }
        if bud.isDone { toggle(id) } else { close(id, cascade: false) }
    }
}

/// The bud a menu's Add inside… plants under, or the read screen opens on.
struct TVAddTarget: Identifiable {
    let id: UUID
}

/// One line of text from the TV keyboard or dictation: in the Inbox from the Capture button, under
/// the bud the person added on otherwise. Return plants, Menu cancels.
struct TVCaptureSheet: View {
    @ObservedObject var store: BudStore
    /// The Inbox from the Capture button, or under the bud the person added on.
    let target: PlantTarget
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var todo = true

    init(store: BudStore, target: PlantTarget) {
        self.store = store
        self.target = target
    }

    init(store: BudStore, parent: UUID) {
        self.init(store: store, target: PlantTarget.forCenter(parent))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            Text(target.title(in: store.tree))
                .textRole(.title)
                .foregroundStyle(Theme.text)
            if target == .inbox {
                Text("Lands in the Inbox. Give it a home later.")
                    .textRole(.caption)
                    .foregroundStyle(Theme.text3)
            }
            TextField("What is it?", text: $text)
                .onSubmit(plant)
            if target != .inbox {
                Picker("Kind", selection: $todo) {
                    Text("To-do").tag(true)
                    Text("Note").tag(false)
                }
                .pickerStyle(.segmented)
            }
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
        store.plant(trimmed, todo: todo, at: target)
        dismiss()
    }
}
#endif
