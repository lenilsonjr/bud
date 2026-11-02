#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// Files on a phone: the navigator (Places, the tree, Lenses) on top, the page below, a handle
/// between them that names where you are. The chevron on the handle folds the navigator away so
/// the page has the whole screen, and brings it back.
struct PhoneFilesView: View {
    @ObservedObject var store: BudStore
    @State private var pageFull = false

    static let handleHeight: CGFloat = 36
    /// The navigator's share of the height: 30 / 70, kept after trying 40 / 60 on a phone.
    static let navigatorShare: Double = 0.3

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                if !pageFull {
                    Sidebar(store: store)
                        .frame(height: (geo.size.height * Self.navigatorShare).rounded(), alignment: .top)
                        .clipped()
                        .background(Theme.sidebar)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                handle
                FilesPage(store: store)
            }
        }
    }

    /// Where you are, and the chevron: down folds the navigator away, up brings it back.
    private var handle: some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(Theme.lineStrong)
                .frame(width: 28, height: 4)
            Text(whereYouAre)
                .textRole(.label)
                .lineLimit(1)
                .foregroundStyle(Theme.text2)
            Spacer(minLength: 8)
            Button {
                withAnimation(.easeOut(duration: 0.2)) { pageFull.toggle() }
            } label: {
                Image(systemName: pageFull ? "chevron.down" : "chevron.up")
                    .foregroundStyle(Theme.text2)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(pageFull ? "Show the navigator" : "Give the page the whole screen")
        }
        .padding(.horizontal, 12)
        .frame(height: Self.handleHeight)
        .frame(maxWidth: .infinity)
        .background(Theme.sidebar)
        .overlay(alignment: .top) { Theme.line.frame(height: 1) }
        .overlay(alignment: .bottom) { Theme.line.frame(height: 1) }
    }

    private var whereYouAre: String {
        if let place = store.place { return place.rawValue }
        if let lens = store.lens { return lens.rawValue }
        return store.tree.title(of: store.center)
    }
}
#endif
