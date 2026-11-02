#if canImport(SwiftUI)
import SwiftUI

/// The canvas: cards positioned by the layout, one camera over all of them, a thin line from
/// every card to its parent so a far card still reads as part of its thread.
/// The camera is the board point at the middle of the viewport; the scale only changes
/// when you pinch. Drag or scroll to move, tap a card with children to center it,
/// tap a leaf to edit it. The light rests on the card under the pointer.
public struct OrbitCanvas: View {
    @ObservedObject var store: BudStore
    @State private var camera: CGPoint = .zero
    @State private var scale: CGFloat = 1
    @State private var dragOrigin: CGPoint? = nil
    @State private var pinchOrigin: CGFloat? = nil
    @State private var lamp: CGPoint? = nil
    @State private var editing: EditTarget? = nil
    @State private var adding: AddTarget? = nil
    @FocusState private var focused: Bool

    private let lampReach: CGFloat = 170

    public init(store: BudStore) {
        self.store = store
    }

    public var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let layout = store.layout
            let lit = litCard(in: layout, viewport: size)
            ZStack {
                Theme.canvas
                    .contentShape(Rectangle())
                    .gesture(panGesture)
                    .onTapGesture { focused = true }
                EdgesLayer(layout: layout, scale: scale) { screenPoint($0, in: size) }
                    .allowsHitTesting(false)
                ForEach(layout.order, id: \.self) { id in
                    if let placed = layout.cards[id] {
                        CardView(
                            id: id,
                            store: store,
                            role: placed.role,
                            lit: lit == id,
                            onTap: { tap(id) },
                            onAdd: { adding = AddTarget(parent: id) },
                            onToggle: { store.toggle(id) }
                        )
                        .scaleEffect(scale)
                        .position(screenPoint(placed.position, in: size))
                        .zIndex(lit == id ? 2 : (placed.role == .center ? 1 : 0))
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
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
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(.escape) {
            stepOut()
            return .handled
        }
        .onChange(of: store.center) { _, _ in
            withAnimation(.spring(duration: 0.8, bounce: 0.12)) { camera = .zero }
        }
        .sheet(item: $editing) { target in EditSheet(store: store, id: target.id) }
        .sheet(item: $adding) { target in AddSheet(store: store, parent: target.parent) }
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
                scale = min(3, max(0.35, origin * value.magnification))
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
            let s = Metrics.size(of: id)
            let dx = max(0, abs(at.x - placed.position.x) - s.width / 2)
            let dy = max(0, abs(at.y - placed.position.y) - s.height / 2)
            let d = hypot(dx, dy)
            if d <= lampReach / scale, best == nil || d < best!.1 { best = (id, d) }
        }
        return best?.0
    }

    private func tap(_ id: UUID) {
        if id == rootID || store.tree.hasChildren(id) {
            if id == store.center {
                if id != rootID { editing = EditTarget(id: id) }
                return
            }
            withAnimation(.spring(duration: 0.8, bounce: 0.12)) { store.center = id }
        } else {
            editing = EditTarget(id: id)
        }
    }

    private func stepOut() {
        withAnimation(.spring(duration: 0.8, bounce: 0.12)) { store.back() }
    }
}

/// The lines: one straight stroke per edge, parent centre to child centre, drawn under the cards.
/// The current thread gets the stronger line; ghost and kin clusters the fainter one.
struct EdgesLayer: View {
    let layout: Layout
    let scale: CGFloat
    let screenPoint: (CGPoint) -> CGPoint

    var body: some View {
        Canvas { context, _ in
            var strong = Path()
            var faint = Path()
            for edge in layout.edges {
                guard let from = layout.cards[edge.from], let to = layout.cards[edge.to] else { continue }
                let a = screenPoint(from.position)
                let b = screenPoint(to.position)
                if to.role == .ghost || to.role == .kin {
                    faint.move(to: a)
                    faint.addLine(to: b)
                } else {
                    strong.move(to: a)
                    strong.addLine(to: b)
                }
            }
            let width = max(0.75, scale)
            context.stroke(strong, with: .color(Theme.lineStrong), lineWidth: width)
            context.stroke(faint, with: .color(Theme.line), lineWidth: width)
        }
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
