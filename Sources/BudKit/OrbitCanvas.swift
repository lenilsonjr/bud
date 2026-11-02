#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// The canvas: cards positioned by the layout, one camera over all of them, a thin line from
/// every card to its parent so a far card still reads as part of its thread.
/// The camera is the board point at the middle of the viewport; the scale only changes
/// when you pinch. Dragging or scrolling moves it, tap a card with children to center it,
/// tap a leaf to open it in place. A soft wash and the light rest under the pointer, or where
/// the last tap landed on touch; the current orbit is in full light, the rest dims; Space opens
/// that card, N plants a bud under it.
public struct OrbitCanvas: View {
    @ObservedObject var store: BudStore
    @State private var camera: CGPoint = .zero
    private var scale: CGFloat { store.zoom }
    @State private var dragOrigin: CGPoint? = nil
    @State private var pinchOrigin: CGFloat? = nil
    @State private var lamp: CGPoint? = nil
    @State private var opened: UUID? = nil
    @State private var viewport: CGSize = .zero
    @FocusState private var focused: Bool
    @State private var motion = MotionState()
    /// Whether the timeline is ticking: it stops once every card is on its spot.
    @State private var animating = true
    @State private var dragging: UUID? = nil
    @State private var dragStart: CGPoint? = nil
    private static let space = "orbit"

    private let lampReach: CGFloat = 170
    /// The wash under the pointer: leaf at 12% fading to nothing over this radius.
    private let washRadius: CGFloat = 260
    /// Where the wash last was, so it can fade out in place when the pointer leaves.
    @State private var washAt: CGPoint = .zero

    public init(store: BudStore) {
        self.store = store
    }

    public var body: some View {
        GeometryReader { geo in
            let size = geo.size
            TimelineView(.animation(paused: !Motion.enabled || !animating)) { timeline in
                canvas(size: size, layout: frame(at: timeline.date))
            }
            .onChange(of: store.layout) { _, _ in animating = true }
            .onAppear { viewport = size }
            .onChange(of: size) { _, now in viewport = now }
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let point): lamp = point
                case .ended: lamp = nil
                }
            }
            .simultaneousGesture(magnifyGesture)
            #if os(macOS)
            .background(ScrollWheelCatcher { dx, dy in
                camera.x -= dx / scale
                camera.y -= dy / scale
            })
            #endif
        }
        // The canvas colour runs under the side and bottom safe areas, so a phone held sideways
        // shows no window-coloured strips around it.
        .background(Theme.canvas.ignoresSafeArea(edges: [.horizontal, .bottom]))
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(.escape) {
            if opened != nil { close() } else { stepOut() }
            return .handled
        }
        .onKeyPress(.space) {
            guard let lit = litCard(in: store.layout, viewport: viewport) else { return .ignored }
            open(lit)
            return .handled
        }
        .onKeyPress(KeyEquivalent("n")) {
            addUnderTheLitCard()
            return .handled
        }
        .onChange(of: store.center) { _, _ in
            opened = nil
            withAnimation(.spring(duration: 0.8, bounce: 0.12)) { camera = .zero }
        }
    }

    /// The layout to draw this frame: the cards where the springs have them, or the static layout
    /// when motion is off. Lines, light and hit tests all read the same positions.
    private func frame(at date: Date) -> Layout {
        guard Motion.enabled else { return store.layout }
        motion.advance(to: date, rest: store.layout)
        if motion.sim.isAtRest, animating, dragging == nil {
            DispatchQueue.main.async { animating = false }
        }
        return motion.sim.current
    }

    private func canvas(size: CGSize, layout: Layout) -> some View {
        let lit = litCard(in: layout, viewport: size)
        let lifted = lit.map { store.tree.orbit(of: $0) } ?? []
        return ZStack {
            Theme.canvas
                .contentShape(Rectangle())
                .gesture(panGesture)
                .onTapGesture(coordinateSpace: .local) { point in
                    focused = true
                    close()
                    lamp = point
                }
            wash
            EdgesLayer(layout: layout, scale: scale, lifted: Set(lifted)) { screenPoint($0, in: size) }
                .allowsHitTesting(false)
            ForEach(layout.order, id: \.self) { id in
                if let placed = layout.cards[id] {
                    CardView(
                        id: id,
                        store: store,
                        role: placed.role,
                        lit: lit == id,
                        light: lightLevel(role: placed.role, lifted: lifted.contains(id)),
                        onTap: { tap(id, at: screenPoint(placed.position, in: size)) },
                        onOpen: { open(id) },
                        onAdd: { store.modal = .adding(under: id) },
                        onToggle: { store.tick(id) }
                    )
                    .scaleEffect(scale)
                    .position(screenPoint(placed.position, in: size))
                    .gesture(dragGesture(id))
                    .zIndex(dragging == id || lit == id ? 2 : (placed.role == .center ? 1 : 0))
                }
            }
            if let opened, let placed = layout.cards[opened] {
                DetailCard(id: opened, store: store, onEnrich: { store.modal = .add(parent: opened) }, onClose: close)
                    .scaleEffect(scale)
                    .position(screenPoint(placed.position, in: size))
                    .zIndex(3)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .coordinateSpace(name: Self.space)
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    /// Pick a card up and let go: the others make room while it is held, and it settles back after.
    private func dragGesture(_ id: UUID) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named(Self.space))
            .onChanged { value in
                guard Motion.enabled else { return }
                if dragging != id {
                    dragging = id
                    dragStart = motion.sim.positions[id]
                }
                guard let start = dragStart else { return }
                motion.sim.hold(id, at: CGPoint(x: start.x + value.translation.width / scale, y: start.y + value.translation.height / scale))
                animating = true
            }
            .onEnded { _ in
                guard dragging == id else { return }
                motion.sim.release(id)
                dragging = nil
                dragStart = nil
                animating = true
            }
    }

    /// The light itself: a soft radial wash that follows the pointer and fades out when it leaves.
    private var wash: some View {
        Circle()
            .fill(RadialGradient(colors: [Theme.leaf.opacity(0.12), Theme.leaf.opacity(0)], center: .center, startRadius: 0, endRadius: washRadius))
            .frame(width: washRadius * 2, height: washRadius * 2)
            .position(lamp ?? washAt)
            .opacity(lamp == nil ? 0 : 1)
            .animation(.easeOut(duration: 0.3), value: lamp == nil)
            .allowsHitTesting(false)
            .onChange(of: lamp) { _, now in if let now { washAt = now } }
    }

    // MARK: camera

    private func screenPoint(_ p: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2 + (p.x - camera.x) * scale, y: size.height / 2 + (p.y - camera.y) * scale)
    }

    private func boardPoint(_ s: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: camera.x + (s.x - size.width / 2) / scale, y: camera.y + (s.y - size.height / 2) / scale)
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .onChanged { value in
                if dragOrigin == nil { dragOrigin = camera }
                guard let origin = dragOrigin else { return }
                camera = CGPoint(x: origin.x - value.translation.width / scale, y: origin.y - value.translation.height / scale)
                lamp = value.location
            }
            .onEnded { value in
                let glideX = value.predictedEndTranslation.width - value.translation.width
                let glideY = value.predictedEndTranslation.height - value.translation.height
                dragOrigin = nil
                withAnimation(.spring(duration: 0.9, bounce: 0)) {
                    camera.x -= glideX / scale * 0.5
                    camera.y -= glideY / scale * 0.5
                }
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if pinchOrigin == nil { pinchOrigin = scale }
                guard let origin = pinchOrigin else { return }
                store.zoom = min(3, max(0.35, origin * value.magnification))
            }
            .onEnded { _ in pinchOrigin = nil }
    }

    // MARK: attention and navigation

    private func litCard(in layout: Layout, viewport: CGSize) -> UUID? {
        guard let lamp else { return nil }
        let at = boardPoint(lamp, in: viewport)
        var best: (UUID, CGFloat)? = nil
        for id in layout.order {
            guard let placed = layout.cards[id] else { continue }
            let s = Metrics.size(hub: placed.hub)
            let dx = max(0, abs(at.x - placed.position.x) - s.width / 2)
            let dy = max(0, abs(at.y - placed.position.y) - s.height / 2)
            let d = hypot(dx, dy)
            if d <= lampReach / scale, best == nil || d < best!.1 { best = (id, d) }
        }
        return best?.0
    }

    /// A card with children centers on the first click and opens on the next; a leaf opens at once.
    /// On touch the light has no pointer to follow, so it rests where the tap landed.
    private func tap(_ id: UUID, at point: CGPoint) {
        lamp = point
        if id == rootID || store.tree.hasChildren(id) {
            if id == store.center {
                if id != rootID { open(id) }
                return
            }
            withAnimation(.spring(duration: 0.8, bounce: 0.12)) { store.center = id }
        } else {
            open(id)
        }
    }

    private func open(_ id: UUID) {
        guard id != rootID else { return }
        withAnimation(.spring(duration: 0.35, bounce: 0.2)) { opened = id }
    }

    private func close() {
        guard opened != nil else { return }
        withAnimation(.easeOut(duration: 0.2)) { opened = nil }
    }

    /// N: a new bud under the lit card, or under the center when nothing is lit. The hub is not
    /// a place to plant under: there N captures.
    private func addUnderTheLitCard() {
        store.modal = .adding(under: litCard(in: store.layout, viewport: viewport) ?? store.center)
    }

    private func stepOut() {
        withAnimation(.spring(duration: 0.8, bounce: 0.12)) { store.back() }
    }
}

/// The simulation and the clock that steps it, held by reference so the timeline can advance it
/// while the view is drawing.
final class MotionState {
    var sim: Simulation
    private var last: Date?

    init() {
        sim = Simulation(layout: Layout(centerID: rootID, cards: [:], order: [], edges: [], orbits: [:], bounds: .zero))
    }

    func advance(to date: Date, rest: Layout) {
        sim.retarget(to: rest)
        let dt = last.map { date.timeIntervalSince($0) } ?? 0
        last = sim.isAtRest ? nil : date
        sim.step(dt: dt)
    }
}

#if os(macOS)
import AppKit

/// Trackpad and mouse-wheel panning: SwiftUI has no scroll-wheel event, so a local monitor hands the deltas up.
struct ScrollWheelCatcher: NSViewRepresentable {
    var onScroll: (CGFloat, CGFloat) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.onScroll = onScroll
    }

    final class CatcherView: NSView {
        var onScroll: ((CGFloat, CGFloat) -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(point) else { return event }
                let factor: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
                self.onScroll?(event.scrollingDeltaX * factor, event.scrollingDeltaY * factor)
                return nil
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}
#endif
#endif
