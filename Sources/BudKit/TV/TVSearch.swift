#if canImport(SwiftUI) && os(tvOS)
import SwiftUI

/// Go anywhere on Apple TV: a full-screen field typed on the one-line keyboard or the iPhone,
/// the hits under it as TV rows with their trail, the recent buds while the field is empty. A
/// click reads the bud over the search; Menu steps back, then closes.
struct TVSearchScreen: View {
    @ObservedObject var store: BudStore
    let close: () -> Void
    @State private var text = ""
    @State private var reading: TVAddTarget? = nil
    @FocusState private var focused: Focus?

    enum Focus: Hashable {
        case field
        case row(UUID)
    }

    private static let title = TextStyle(typeface: .display, size: 64, weight: 500)
    private static let code = TextStyle(typeface: .text, size: 36, weight: 400)
    private static let aside = TextStyle(typeface: .text, size: 24, weight: 400)
    private static let eyebrow = TextStyle(typeface: .text, size: 20, weight: 700, tracking: 1.6, uppercase: true)
    private static let empty = TextStyle(typeface: .text, size: 26, weight: 400)

    private var hits: [SearchHit] { TreeSearcher(tree: store.tree).search(text, limit: 12) }
    private var rows: [TVFilesRow] { hits.compactMap { TVFilesText.row($0.id, in: store.tree) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 34) {
            Text(TVSearchText.title)
                .textStyle(Self.title)
                .foregroundStyle(Theme.text)
            field
            HStack(spacing: 14) {
                Image(systemName: "iphone")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Theme.leaf)
                Text(TVSearchText.phoneKeyboard)
                    .textStyle(Self.aside)
                    .foregroundStyle(Theme.text2)
            }
            Text(TVSearchText.heading(query: text, hits: hits.count))
                .textStyle(Self.eyebrow)
                .foregroundStyle(Theme.leaf)
                .padding(.top, 10)
            if rows.isEmpty {
                Text(TVSearchText.empty(query: text))
                    .textStyle(Self.empty)
                    .foregroundStyle(Theme.text3)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(rows, id: \.id) { row in
                            TVBudRow(row: row, lit: focused == .row(row.id), now: store.now) { reading = TVAddTarget(id: row.id) }
                                .focused($focused, equals: .row(row.id))
                                .budMenu(row.id, store: store, onOpen: { reading = TVAddTarget(id: row.id) })
                        }
                    }
                    .padding(.vertical, 30)
                }
                .scrollClipDisabled()
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 80)
        .padding(.horizontal, 200)
        .padding(.bottom, 80)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.window.ignoresSafeArea())
        .textRole(.body)
        .foregroundStyle(Theme.text)
        .fullScreenCover(item: $reading) { target in TVReadScreen(store: store, start: target.id, close: { reading = nil }) }
        .onExitCommand {
            if case .row = focused { focused = .field } else { close() }
        }
        .onAppear { focused = .field }
    }

    private var field: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        return HStack(spacing: 20) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(Theme.text3)
            TextField(TVSearchText.placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(Theme.font(Self.code))
                .foregroundStyle(Theme.text)
                .autocorrectionDisabled()
                .focused($focused, equals: .field)
                .onSubmit { if let first = rows.first { focused = .row(first.id) } }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity)
        .background(Theme.raised, in: shape)
        .overlay(shape.stroke(focused == .field ? Theme.amethyst : Theme.lineStrong, lineWidth: focused == .field ? 2 : 1))
    }
}
#endif
