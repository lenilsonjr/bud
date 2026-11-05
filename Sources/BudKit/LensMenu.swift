#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// The rows a lens can tick: the built-in questions, then the tags in use, then the buds picked
/// under "Linked to…", each with how many buds answer it alone. Ticked rows combine, and the canvas lights the answer while the menu is
/// open. The footer counts the buds that answer every ticked row.
struct LensMenu: View {
    @ObservedObject var store: BudStore
    /// Whether "Linked to…" has opened its search.
    @State private var linking = false
    @State private var linkQuery = ""
    @FocusState private var typing: Bool

    /// The tags the menu offers: the most used, up to this many.
    static let tagLimit = 8
    /// The buds "Linked to…" offers at once.
    static let linkLimit = 5

    var body: some View {
        let tags = store.tree.tagCounts().prefix(Self.tagLimit).map { LensFacet.tag($0.tag) }
        VStack(alignment: .leading, spacing: 2) {
            section("Built in", LensFacet.builtIns)
            if !tags.isEmpty { section("Tags", Array(tags)) }
            links
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

    /// The buds picked so far, each a row to untick, then "Linked to…", which opens a search over
    /// the buds that have links, the most linked first.
    private var links: some View {
        let picked = store.canvasFacets.filter { if case .linked = $0 { return true } else { return false } }
        return VStack(alignment: .leading, spacing: 2) {
            if !picked.isEmpty { section("Links", picked) }
            if linking {
                let candidates = candidates
                HStack(spacing: 6) {
                    TextField("Linked to…", text: $linkQuery)
                        .textFieldStyle(.plain)
                        .focused($typing)
                        .onSubmit { if let first = candidates.first { pick(first.bud) } }
                        .accessibilityIdentifier("lens-linked-search")
                    Button {
                        linking = false
                        linkQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.text3)
                            .contentShape(Rectangle().inset(by: -6))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Stop picking a bud")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).stroke(Theme.leafLine, lineWidth: 1))
                // A hop past the field's first frame, which a popover would otherwise drop.
                .task { typing = true }
                ForEach(candidates, id: \.bud.id) { candidate in
                    let count = candidate.count
                    Button { pick(candidate.bud) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "link").foregroundStyle(Theme.text2).frame(width: 16)
                            Text(candidate.bud.text).lineLimit(1).foregroundStyle(Theme.text)
                            Spacer(minLength: 8)
                            Text("\(count)")
                                .textRole(.caption)
                                .monospacedDigit()
                                .foregroundStyle(Theme.text3)
                        }
                        .textRole(.body)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Linked to \(candidate.bud.text), \(count == 1 ? "1 bud" : "\(count) buds")")
                }
                if candidates.isEmpty {
                    Text(linkQuery.isEmpty ? "No links yet." : "Nothing matches.")
                        .textRole(.caption)
                        .foregroundStyle(Theme.text3)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                }
            } else {
                Button {
                    linking = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "link").foregroundStyle(Theme.text2).frame(width: 16)
                        Text("Linked to…").foregroundStyle(Theme.text)
                        Spacer(minLength: 8)
                    }
                    .textRole(.body)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, picked.isEmpty ? 6 : 0)
                .accessibilityIdentifier("lens-linked-to")
            }
        }
    }

    /// Buds with links, not picked yet, whose title has what is typed, the most linked first,
    /// each with how many buds on the canvas it is linked with: what ticking it would light.
    private var candidates: [(bud: Bud, count: Int)] {
        let typed = BudLinks.fold(linkQuery.trimmingCharacters(in: .whitespaces))
        let picked = Set(store.canvasFacets.compactMap { facet -> UUID? in
            if case .linked(let id, _) = facet { return id } else { return nil }
        })
        let canvas = store.tree.walk(under: rootID)
        let onCanvas = Set(canvas.map(\.id))
        return canvas
            .filter { !picked.contains($0.id) && (typed.isEmpty || BudLinks.fold($0.text).contains(typed)) }
            .map { bud in (bud, store.links.around(bud.id).filter { onCanvas.contains($0.other) }.count) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.text < $1.0.text }
            .prefix(Self.linkLimit)
            .map { (bud: $0.0, count: $0.1) }
    }

    private func pick(_ bud: Bud) {
        withAnimation(.easeOut(duration: 0.35)) { store.canvasFacets.append(.linked(bud.id, title: bud.text)) }
        linking = false
        linkQuery = ""
    }

    private func row(_ facet: LensFacet) -> some View {
        let ticked = store.canvasFacets.contains(facet)
        let count = facet.query.hits(store.tree, links: store.links).count
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
                Text(store.facetName(facet))
                    .lineLimit(1)
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
        .accessibilityLabel("\(store.facetName(facet)), \(count == 1 ? "1 bud" : "\(count) buds")")
        .accessibilityAddTraits(ticked ? .isSelected : [])
    }

    @ViewBuilder private var footer: some View {
        HStack {
            if store.canvasFacets.isEmpty {
                Text("Tick rows to light what matches")
            } else {
                let hits = store.canvasLens?.hits(store.tree, links: store.links).count ?? 0
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
