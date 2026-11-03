/// Go anywhere on a phone: what opens the palette's sheet, and where a tap on a hit goes.
public enum PhonePalette {
    /// How far the navigator is pulled down, in points, before the palette opens.
    public static let pull: Double = 80

    /// Follows the navigator's top edge as it scrolls: the palette opens once when the edge is
    /// pulled past the threshold, and can open again only after the navigator has rested.
    public struct Pull: Equatable, Sendable {
        private var rest: Double?
        private var armed = true

        public init() {}

        /// Feeds the top edge's position; true the moment the palette should open.
        public mutating func offset(_ y: Double) -> Bool {
            guard let rest else {
                self.rest = y
                return false
            }
            let pulled = y - rest
            if pulled <= 0 {
                armed = true
                return false
            }
            guard armed, pulled >= PhonePalette.pull else { return false }
            armed = false
            return true
        }
    }

    /// A tap goes where you already are: in Files it selects the hit, on the canvas it centers
    /// it. A long press offers the other way, by this name.
    public static func otherWay(inFiles: Bool) -> String {
        inFiles ? "Center on canvas" : "Open in Files"
    }
}
