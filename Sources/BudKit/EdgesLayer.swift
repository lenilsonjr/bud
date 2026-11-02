#if canImport(SwiftUI)
import SwiftUI

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
#endif
