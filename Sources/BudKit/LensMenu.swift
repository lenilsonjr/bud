#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// The rows a lens can tick: the built-in questions, then the tags in use, each with how many
/// buds answer it alone. Ticked rows combine, and the canvas lights the answer while the menu is
/// open. The footer counts the buds that answer every ticked row.
struct LensMenu: View {
    @ObservedObject var store: BudStore

    /// The tags the menu offers: the most used, up to this many.
    static let tagLimit = 8

    var body: some View {
        let tags = store.tree.tagCounts().prefix(Self.tagLimit).map { LensFacet.tag($0.tag) }
        VStack(alignment: .leading, spacing: 2) {
            section("Built in", LensFacet.builtIns)
            if !tags.isEmpty { section("Tags", Array(tags)) }
            Divider().padding(.vertical, 4)
            footer
        }
        .padding(8)
        .frame(width: 300, alignment: .leading)
        .accessibilityIdentifier("lens-menu")
    }

    private func section(_ title: String, _ facets: [LensFacet]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .textRole(.eyebrow)
                .foregroundStyle(Theme.text3)
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 2)
            ForEach(facets, id: \.self) { facet in row(facet) }
        }
    }

    private func row(_ facet: LensFacet) -> some View {
        let ticked = store.canvasFacets.contains(facet)
        let count = facet.query.hits(store.tree).count
        return Button {
            withAnimation(.easeOut(duration: 0.35)) {
                if ticked { store.canvasFacets.removeAll { $0 == facet } } else { store.canvasFacets.append(facet) }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: ticked ? "checkmark.square.fill" : "square")
                    .foregroundStyle(ticked ? Theme.leaf : Theme.text3)
                if case .tag = facet {} else {
                    Image(systemName: facet.systemImage)
                        .foregroundStyle(Theme.text2)
                        .frame(width: 16)
                }
                Text(facet.name)
                    .fontWeight(ticked ? .semibold : .regular)
                    .foregroundStyle(Theme.text)
                Spacer(minLength: 8)
                Text("\(count)")
                    .textRole(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.text3)
            }
            .textRole(.body)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(ticked ? Theme.leafSoft : .clear, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(facet.name), \(count == 1 ? "1 bud" : "\(count) buds")")
        .accessibilityAddTraits(ticked ? .isSelected : [])
    }

    @ViewBuilder private var footer: some View {
        HStack {
            if store.canvasFacets.isEmpty {
                Text("Tick rows to light what matches")
            } else {
                let hits = store.canvasLens?.hits(store.tree).count ?? 0
                Text(Self.footerText(hits: hits, rows: store.canvasFacets.count))
                Spacer()
                Button("Clear") {
                    withAnimation(.easeOut(duration: 0.35)) { store.canvasFacets = [] }
                }
                .buttonStyle(.budGhost)
            }
        }
        .textRole(.caption)
        .foregroundStyle(Theme.leaf)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }

    /// "13 matches" for one row; "2 match both" or "1 matches all" for more.
    static func footerText(hits: Int, rows: Int) -> String {
        guard hits > 0 else { return "Nothing matches" }
        guard rows > 1 else { return hits == 1 ? "1 match" : "\(hits) matches" }
        let every = rows == 2 ? "both" : "all"
        return hits == 1 ? "1 matches \(every)" : "\(hits) match \(every)"
    }
}
#endif
