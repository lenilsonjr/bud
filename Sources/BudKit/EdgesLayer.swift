#if canImport(SwiftUI)
import SwiftUI

/// The lines from every card to its parent, drawn once in one canvas. Each line takes the light
/// of the card at its far end, so a line never runs across a dimmed card at full strength.
struct EdgesLayer: View {
    let layout: Layout
    let scale: CGFloat
    var lifted: Set<UUID> = []
    let screenPoint: (CGPoint) -> CGPoint

    var body: some View {
        Canvas { context, _ in
            var paths: [Double: Path] = [:]
            for edge in layout.edges {
                guard let from = layout.cards[edge.from], let to = layout.cards[edge.to] else { continue }
                let level = lightLevel(role: to.role, lifted: lifted.contains(to.id))
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
