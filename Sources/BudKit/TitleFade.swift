import Foundation

/// The rule for a sidebar title that sits beside a count: it fades under the count only when it
/// is wider than the room it has; a title that fits is drawn whole.
enum TitleFade {
    /// Measuring noise below this many points is not an overlap.
    static let tolerance: CGFloat = 0.5

    static func needsFade(textWidth: CGFloat, availableWidth: CGFloat) -> Bool {
        textWidth > availableWidth + tolerance
    }
}
