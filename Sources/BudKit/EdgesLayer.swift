#if canImport(SwiftUI)
import SwiftUI

/// The lines from every card to its parent, drawn once in one canvas. Each line takes the light
/// of the card at its far end, so a line never runs across a dimmed card at full strength; under
/// a lens that is the lens's light, so the lines trace the path down to the hits.
struct EdgesLayer: View {
    let layout: Layout
    let scale: CGFloat
    var lifted: Set<UUID> = []
    /// How each bud stands under the canvas lens; nil when no lens is on.
    var lens: [UUID: LensQuery.Match]? = nil
    let screenPoint: (CGPoint) -> CGPoint

    var body: some View {
        Canvas { context, _ in
            var paths: [Double: Path] = [:]
            for edge in layout.edges {
                guard let from = layout.cards[edge.from], let to = layout.cards[edge.to] else { continue }
                let level = lensLevel(
                    lightLevel(role: to.role, lifted: lifted.contains(to.id)),
                    match: lens?[to.id],
                    lensOn: lens != nil
                )
                paths[level, default: Path()].move(to: screenPoint(from.position))
                paths[level, default: Path()].addLine(to: screenPoint(to.position))
            }
            let width = max(0.75, scale)
            for (level, path) in paths.sorted(by: { $0.key < $1.key }) {
                context.stroke(path, with: .color(Theme.lineStrong.opacity(level)), lineWidth: width)
            }
        }
    }
}
#endif
