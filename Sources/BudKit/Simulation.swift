import Foundation

/// Whether cards drift on springs. Off, the canvas draws the static layout, so a screenshot test
/// sees every card on its rest spot.
public enum Motion {
    public static let enabled = true
}

/// A small spring simulation over a `Layout`. The layout's positions are the rest spots: every
/// card is pulled toward its own with a critically damped spring, and cards that overlap push each
/// other apart. A card being held stays where it is until it is let go. Once every card is on its
/// spot the simulation is at rest and a step costs nothing.
public struct Simulation {
    /// Spring stiffness as an angular frequency: a card is within a point of its spot well inside a second.
    public static let omega: Double = 10
    /// Acceleration per point of overlap, per second squared.
    public static let push: Double = 40
    /// The longest slice stepped at once, so a long pause cannot fling a card.
    public static let slice: Double = 1.0 / 60
    public static let longest: Double = 0.1

    public private(set) var layout: Layout
    public private(set) var positions: [UUID: CGPoint]
    private var velocities: [UUID: Vector]
    private var held: Set<UUID> = []
    public private(set) var isAtRest: Bool

    public init(layout: Layout) {
        self.layout = layout
        positions = layout.cards.mapValues(\.position)
        velocities = [:]
        isAtRest = true
    }

    /// The layout with every card where the simulation has it now. Lines and light follow this.
    public var current: Layout {
        var out = layout
        for (id, p) in positions { out.cards[id]?.position = p }
        return out
    }

    /// New rest spots. Cards already on the canvas keep their place and velocity and drift to the
    /// new spot; a new card appears at a neighbour it is linked to, or on its own spot.
    public mutating func retarget(to next: Layout) {
        guard next != layout else { return }
        var moved: [UUID: CGPoint] = [:]
        let here = positions
        for (id, card) in next.cards {
            if let p = here[id] {
                moved[id] = p
            } else if let near = next.edges.lazy.compactMap({ e -> CGPoint? in
                e.from == id ? here[e.to] : (e.to == id ? here[e.from] : nil)
            }).first {
                moved[id] = near
            } else {
                moved[id] = card.position
            }
        }
        positions = moved
        velocities = velocities.filter { next.cards[$0.key] != nil }
        held = held.filter { next.cards[$0] != nil }
        layout = next
        isAtRest = false
    }

    /// Pick a card up: it follows `point` and others make room for it.
    public mutating func hold(_ id: UUID, at point: CGPoint) {
        guard positions[id] != nil else { return }
        held.insert(id)
        positions[id] = point
        velocities[id] = .zero
        isAtRest = false
    }

    /// Let go: the card settles back to its spot.
    public mutating func release(_ id: UUID) {
        guard held.remove(id) != nil else { return }
        isAtRest = false
    }

    /// Knock a card away from its spot by an offset, as if it had been dragged and let go.
    public mutating func displace(_ id: UUID, by offset: Vector) {
        guard let p = positions[id] else { return }
        positions[id] = CGPoint(x: p.x + offset.dx, y: p.y + offset.dy)
        isAtRest = false
    }

    public mutating func step(dt: Double) {
        guard !isAtRest, dt > 0 else { return }
        var left = min(dt, Self.longest)
        while left > 0 {
            let h = min(left, Self.slice)
            advance(h)
            left -= h
        }
        if settled() { snap() }
    }

    private mutating func advance(_ h: Double) {
        let ids = layout.order
        var accel: [UUID: Vector] = [:]
        for i in ids.indices {
            guard let a = layout.cards[ids[i]], let pa = positions[ids[i]] else { continue }
            let sa = Metrics.size(hub: a.hub)
            for j in ids.indices where j > i {
                guard let b = layout.cards[ids[j]], let pb = positions[ids[j]] else { continue }
                let sb = Metrics.size(hub: b.hub)
                let dx = Double(pa.x - pb.x), dy = Double(pa.y - pb.y)
                let ox = Double(sa.width + sb.width) / 2 - abs(dx)
                let oy = Double(sa.height + sb.height) / 2 - abs(dy)
                guard ox > 0, oy > 0 else { continue }
                var ux = 0.0, uy = 0.0
                if ox < oy {
                    ux = (dx == 0 ? (ids[i].uuidString < ids[j].uuidString ? 1 : -1) : (dx > 0 ? 1 : -1)) * ox * Self.push
                } else {
                    uy = (dy == 0 ? (ids[i].uuidString < ids[j].uuidString ? 1 : -1) : (dy > 0 ? 1 : -1)) * oy * Self.push
                }
                accel[ids[i], default: .zero] = accel[ids[i], default: .zero] + Vector(dx: ux, dy: uy)
                accel[ids[j], default: .zero] = accel[ids[j], default: .zero] - Vector(dx: ux, dy: uy)
            }
        }

        let w = Self.omega
        let e = exp(-w * h)
        for id in ids {
            guard !held.contains(id), let p = positions[id], let rest = layout.cards[id]?.position else { continue }
            var v = velocities[id] ?? .zero
            if let a = accel[id] { v = Vector(dx: v.dx + a.dx * h, dy: v.dy + a.dy * h) }
            // Exact step of x'' = -w^2 x - 2 w x', so the spring never overshoots and never rings.
            let dx = Double(p.x - rest.x), dy = Double(p.y - rest.y)
            let kx = Double(v.dx) + w * dx, ky = Double(v.dy) + w * dy
            positions[id] = CGPoint(x: Double(rest.x) + (dx + kx * h) * e, y: Double(rest.y) + (dy + ky * h) * e)
            velocities[id] = Vector(dx: (Double(v.dx) - w * kx * h) * e, dy: (Double(v.dy) - w * ky * h) * e)
        }
    }

    private func settled() -> Bool {
        guard held.isEmpty else { return false }
        for (id, card) in layout.cards {
            guard let p = positions[id] else { continue }
            let v = velocities[id] ?? .zero
            if hypot(p.x - card.position.x, p.y - card.position.y) > 0.05 || hypot(v.dx, v.dy) > 0.5 { return false }
        }
        return true
    }

    private mutating func snap() {
        positions = layout.cards.mapValues(\.position)
        velocities = [:]
        isAtRest = true
    }
}

/// A displacement or a velocity in points. Foundation has no `CGVector` on Linux.
public struct Vector: Equatable, Sendable {
    public var dx: Double
    public var dy: Double

    public init(dx: Double, dy: Double) {
        self.dx = dx
        self.dy = dy
    }

    public static let zero = Vector(dx: 0, dy: 0)
    static func + (a: Vector, b: Vector) -> Vector { Vector(dx: a.dx + b.dx, dy: a.dy + b.dy) }
    static func - (a: Vector, b: Vector) -> Vector { Vector(dx: a.dx - b.dx, dy: a.dy - b.dy) }
}
