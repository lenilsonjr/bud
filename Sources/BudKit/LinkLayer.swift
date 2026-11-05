#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// The lit card's links, the canvas's second layer: a dotted leaf curve to each bud it links
/// with, a dot at the end a link points to, and for a bud off the canvas a chip on its side with
/// the bud's title and where it lives; a click on the chip goes there. Links show for the lit
/// card only, so the parent lines stay the canvas's one web. The curves sit under the cards and
/// the chips above them, so the canvas draws the layer twice.
struct LinkLayer: View {
    enum Part { case lines, chips }

    let part: Part
    let lit: UUID?
    let layout: Layout
    let graph: LinkGraph
    let tree: Tree
    let scale: CGFloat
    let size: CGSize
    let screenPoint: (CGPoint) -> CGPoint
    let go: (UUID) -> Void
    var hover: (Bool) -> Void = { _ in }

    private static let chip = CGSize(width: 220, height: 28)
    private static let inset: CGFloat = 130

    var body: some View {
        if let lit, let placed = layout.cards[lit] {
            let around = graph.around(lit)
            // As many chips as fit down the side without overlapping; the rest wait on the page.
            let room = Int(size.height * 0.6 / (Self.chip.height + 6)) + 1
            let off = Array(around.filter { layout.cards[$0.other] == nil }.prefix(max(room, 1)))
            let litPoint = screenPoint(placed.position)
            let slots = LinkGeometry.ghostSlots(count: off.count, lit: litPoint, in: size, inset: Self.inset)
            switch part {
            case .lines:
                Canvas { context, _ in
                    let litSize = scaled(Metrics.size(hub: placed.hub))
                    for link in around {
                        let far: CGPoint, farSize: CGSize
                        if let other = layout.cards[link.other] {
                            far = screenPoint(other.position)
                            farSize = scaled(Metrics.size(hub: other.hub))
                        } else if let i = off.firstIndex(where: { $0.other == link.other }) {
                            far = slots[i]
                            farSize = Self.chip
                        } else { continue }
                        let a = LinkGeometry.edge(of: litPoint, size: litSize, toward: far)
                        let b = LinkGeometry.edge(of: far, size: farSize, toward: litPoint)
                        var curve = Path()
                        curve.move(to: a)
                        curve.addQuadCurve(to: b, control: LinkGeometry.bow(from: a, to: b))
                        context.stroke(
                            curve, with: .color(Theme.leaf),
                            style: StrokeStyle(lineWidth: max(1.5, 2 * scale), lineCap: .round, dash: [0.1, 7 * max(scale, 0.6)])
                        )
                        let end = link.outgoing ? b : a
                        let r = max(2.5, 3.5 * scale)
                        context.fill(Path(ellipseIn: CGRect(x: end.x - r, y: end.y - r, width: 2 * r, height: 2 * r)), with: .color(Theme.leaf))
                    }
                }
                .allowsHitTesting(false)
            case .chips:
                ZStack {
                    ForEach(Array(off.enumerated()), id: \.element.other) { i, link in
                        Button { go(link.other) } label: { ghost(link.other) }
                            .buttonStyle(.plain)
                            .onHover(perform: hover)
                            .position(slots[i])
                    }
                }
                .frame(width: size.width, height: size.height)
            }
        }
    }

    private func scaled(_ s: CGSize) -> CGSize { CGSize(width: s.width * scale, height: s.height * scale) }

    private func ghost(_ id: UUID) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "link")
                .foregroundStyle(Theme.leaf)
            Text(tree.title(of: id))
                .fontWeight(.semibold)
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            if let place = tree.trail(of: id).last {
                Text("in \(place)")
                    .foregroundStyle(Theme.text3)
                    .lineLimit(1)
            }
            Image(systemName: "arrow.up.right")
                .foregroundStyle(Theme.text3)
        }
        .textRole(.caption)
        .padding(.horizontal, 10)
        .frame(height: Self.chip.height)
        .frame(maxWidth: Self.chip.width)
        .background(Theme.leafSoft, in: Capsule())
        .overlay(Capsule().stroke(Theme.leafLine, lineWidth: 1))
        .contentShape(Capsule())
        .accessibilityLabel("Go to \(tree.title(of: id))")
    }
}
#endif
