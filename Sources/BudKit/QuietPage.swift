#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// A view that is not built yet: its name over one line saying it is coming, on the page column
/// and nothing else, so the switch lands somewhere quiet and the center stays where it was.
struct QuietPage: View {
    let surface: Surface

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("View")
                .textRole(.eyebrow)
                .foregroundStyle(Theme.leaf)
            Text(surface.rawValue)
                .textRole(.title)
                .foregroundStyle(Theme.text)
            Text(surface.comingLine)
                .textRole(.body)
                .foregroundStyle(Theme.text3)
        }
        .pageColumn()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.canvas)
    }
}
#endif
