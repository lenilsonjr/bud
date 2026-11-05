import Foundation

/// Where the canvas draws a link: the curve leaves and meets cards at their edges, bowed so it
/// never lies along a parent line, and links to buds off the canvas end at chips on its side.
public enum LinkGeometry {
    /// The point where the line from a card's center toward `toward` leaves the card.
    public static func edge(of center: CGPoint, size: CGSize, toward: CGPoint) -> CGPoint {
        let dx = toward.x - center.x, dy = toward.y - center.y
        guard dx != 0 || dy != 0 else { return center }
        let sx = dx == 0 ? CGFloat.infinity : (size.width / 2) / abs(dx)
        let sy = dy == 0 ? CGFloat.infinity : (size.height / 2) / abs(dy)
        let t = min(sx, sy, 1)
        return CGPoint(x: center.x + dx * t, y: center.y + dy * t)
    }

    /// The control point of the curve from `a` to `b`: a quarter of their distance off the
    /// straight line, to the left of the way it runs.
    public static func bow(from a: CGPoint, to b: CGPoint) -> CGPoint {
        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        return CGPoint(x: mid.x + (a.y - b.y) / 4, y: mid.y + (b.x - a.x) / 4)
    }

    /// Where `count` chips for buds off the canvas sit: down the side away from the lit card,
    /// spread over the middle of the height, `inset` in from the edge.
    public static func ghostSlots(count: Int, lit: CGPoint, in size: CGSize, inset: CGFloat) -> [CGPoint] {
        guard count > 0 else { return [] }
        let x = lit.x < size.width / 2 ? size.width - inset : inset
        let top = size.height * 0.2, span = size.height * 0.6
        return (0..<count).map { i in
            CGPoint(x: x, y: count == 1 ? size.height / 2 : top + span * CGFloat(i) / CGFloat(count - 1))
        }
    }
}
