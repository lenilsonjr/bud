import Foundation

/// Flat web of orbits: every card is full size at every depth. Each subtree owns a wedge of
/// directions from the apex it hangs from, sized by how much it holds. The first layer sits evenly
/// around its hub; deeper children orbit their parent along their wedge rays, just far enough out
/// to clear one another and everything already placed. Depth sprawls outward. The center's
/// ancestors trail off up and to the left with the rest of the world around them, so the way
/// back is always on the canvas.
public enum CardRole: String, Sendable {
    case center, ring, deep, ghost, kin
}

/// How bright a card is at rest: the center and its ring in full light, everything outside
/// that orbit dimmed, unless the light has lifted its orbit.
public func lightLevel(role: CardRole, lifted: Bool) -> Double {
    switch role {
    case .center, .ring: return 1
    case .deep, .ghost, .kin: return lifted ? 1 : 0.35
    }
}

public struct Placed: Equatable {
    public var id: UUID
    public var position: CGPoint
    public var role: CardRole
    public var depth: Int
}

public struct Orbit: Equatable {
    public var id: UUID
    public var center: CGPoint
    public var rx: CGFloat
    public var ry: CGFloat
    public var full: Bool
    public var start: Double
    public var wedge: Double
}

public struct Edge: Hashable, Sendable {
    public var from: UUID
    public var to: UUID
}

public struct Layout: Equatable {
    public var centerID: UUID
    public var cards: [UUID: Placed]
    /// Placement order: parents before children, so drawing in this order stacks sensibly.
    public var order: [UUID]
    public var edges: [Edge]
    public var orbits: [UUID: Orbit]
    public var bounds: CGRect

    public func position(of id: UUID) -> CGPoint? { cards[id]?.position }
}

public enum Metrics {
    public static let chip = CGSize(width: 180, height: 80)
    public static let hub = CGSize(width: 170, height: 146)
    public static let gap: CGFloat = 24
    public static let ringStretch: CGFloat = 1.5
    public static let ghostAngle = -5 * Double.pi / 6
    public static let ghostGap: CGFloat = 48

    public static func size(of id: UUID) -> CGSize { id == rootID ? hub : chip }
    public static func halfDiagonal(of id: UUID) -> CGFloat { id == rootID ? 112 : 98 }
}

public enum LayoutEngine {
    public static func layout(of tree: Tree, center: UUID) -> Layout {
        var b = Builder(tree: tree)
        b.put(center, at: .zero, role: .center, depth: 0)
        b.placeChildren(of: center, at: .zero, role: .center, depth: 0, exclude: nil, apex: .zero, start: -Double.pi / 2, wedge: 2 * Double.pi)

        let ang = Metrics.ghostAngle, ux = CGFloat(cos(ang)), uy = CGFloat(sin(ang))
        var prev = center
        var depth = -1
        var next = tree.parent(of: center)
        while let ghost = next {
            let reach = b.cards.map { id, c in c.position.x * ux + c.position.y * uy + Metrics.halfDiagonal(of: id) }.max() ?? 0
            let d = reach + Metrics.halfDiagonal(of: ghost) + Metrics.ghostGap
            let pos = CGPoint(x: d * ux, y: d * uy)
            b.put(ghost, at: pos, role: .ghost, depth: depth)
            b.edges.append(Edge(from: ghost, to: prev))
            b.placeChildren(of: ghost, at: pos, role: .ghost, depth: depth, exclude: prev, apex: pos, start: ang - Double.pi / 2, wedge: Double.pi)
            prev = ghost
            depth -= 1
            next = tree.parent(of: ghost)
        }

        var bounds = CGRect.null
        for (id, c) in b.cards {
            let s = Metrics.size(of: id)
            bounds = bounds.union(CGRect(x: c.position.x - s.width / 2, y: c.position.y - s.height / 2, width: s.width, height: s.height))
        }
        return Layout(centerID: center, cards: b.cards, order: b.order, edges: b.edges, orbits: b.orbits, bounds: bounds.isNull ? .zero : bounds)
    }
}

private struct Builder {
    let tree: Tree
    var cards: [UUID: Placed] = [:]
    var order: [UUID] = []
    var edges: [Edge] = []
    var orbits: [UUID: Orbit] = [:]

    func weight(_ id: UUID, excluding: UUID?) -> Int {
        1 + tree.children(of: id).filter { $0.id != excluding }.reduce(0) { $0 + weight($1.id, excluding: nil) }
    }

    /// A spot is clear when no card already on the canvas comes within a gap of it.
    func isClear(_ p: CGPoint, size: CGSize) -> Bool {
        for (id, c) in cards {
            let o = Metrics.size(of: id)
            if abs(c.position.x - p.x) < (o.width + size.width) / 2 + Metrics.gap,
               abs(c.position.y - p.y) < (o.height + size.height) / 2 + Metrics.gap {
                return false
            }
        }
        return true
    }

    mutating func put(_ id: UUID, at p: CGPoint, role: CardRole, depth: Int) {
        cards[id] = Placed(id: id, position: p, role: role, depth: depth)
        order.append(id)
    }

    mutating func placeChildren(of id: UUID, at pos: CGPoint, role: CardRole, depth: Int, exclude: UUID?, apex: CGPoint, start: Double, wedge: Double) {
        let kids = tree.children(of: id).filter { $0.id != exclude }
        guard !kids.isEmpty else { return }
        let n = kids.count
        let full = role == .center
        let stretch: CGFloat = full ? Metrics.ringStretch : 1
        let need = Metrics.chip.width + Metrics.gap

        let weights = kids.map { weight($0.id, excluding: nil) }
        let sum = Double(weights.reduce(0, +))
        let slices = weights.map { wedge * Double($0) / sum }
        var a = full ? start - slices[0] / 2 : start
        let rays: [Double] = slices.map { s in
            let mid = a + s / 2
            a += s
            return mid
        }

        let D = hypot(pos.x - apex.x, pos.y - apex.y)
        let theta = Double(atan2(pos.y - apex.y, pos.x - apex.x))
        let near = D < 1
        let clearance = Metrics.halfDiagonal(of: id) + (kids.map { Metrics.halfDiagonal(of: $0.id) }.max() ?? 0) + Metrics.gap

        var rho = clearance
        var spots: [CGPoint?] = []
        for _ in 0..<400 {
            spots = rays.enumerated().map { i, ray in
                if near {
                    let phi = start + (full ? Double(i) * wedge / Double(n) : (Double(i) + 0.5) * wedge / Double(n))
                    return CGPoint(x: pos.x + rho * stretch * CGFloat(cos(phi)), y: pos.y + rho * CGFloat(sin(phi)))
                }
                let d = ray - theta
                let s = D * CGFloat(sin(d))
                if abs(s) >= rho { return nil }
                let R = D * CGFloat(cos(d)) + (rho * rho - s * s).squareRoot()
                if R < D { return nil }
                return CGPoint(x: apex.x + R * CGFloat(cos(ray)), y: apex.y + R * CGFloat(sin(ray)))
            }
            var ok = true
            for i in 0..<n {
                guard let p = spots[i] else { ok = false; break }
                if !near {
                    let R = hypot(p.x - apex.x, p.y - apex.y)
                    if R * CGFloat(slices[i]) < need { ok = false; break }
                }
                if i > 0, let q = spots[i - 1], hypot(p.x - q.x, p.y - q.y) < need { ok = false; break }
                if !isClear(p, size: Metrics.size(of: kids[i].id)) { ok = false; break }
            }
            if ok { break }
            rho *= 1.06
        }
        let placed: [CGPoint] = spots.enumerated().map { i, s in
            s ?? CGPoint(x: pos.x + rho * CGFloat(cos(rays[i])), y: pos.y + rho * CGFloat(sin(rays[i])))
        }

        orbits[id] = Orbit(id: id, center: pos, rx: rho * stretch, ry: rho, full: full, start: start, wedge: wedge)
        let childRole: CardRole = role == .center ? .ring : (role == .ghost || role == .kin) ? .kin : .deep
        for (i, kid) in kids.enumerated() {
            edges.append(Edge(from: id, to: kid.id))
            put(kid.id, at: placed[i], role: childRole, depth: depth + 1)
        }
        for (i, kid) in kids.enumerated() {
            placeChildren(of: kid.id, at: placed[i], role: childRole, depth: depth + 1, exclude: nil, apex: apex, start: rays[i] - slices[i] / 2, wedge: slices[i])
        }
    }
}
