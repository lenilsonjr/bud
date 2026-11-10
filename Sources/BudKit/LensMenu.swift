#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// The rows a lens can tick: the built-in questions, then the tags in use, the sources buds came
/// from, and the buds picked under "Linked to…", each with how many buds answer it alone. Ticked rows combine, and the canvas lights the answer while the menu is
/// open. The footer counts the buds that answer every ticked row and keeps them as a saved
/// lens; the saved lenses sit on top, each a tap from asking its question again.
struct LensMenu: View {
    @ObservedObject var store: BudStore
    /// Whether "Linked to…" has opened its search.
    @State private var linking = false
    @State private var linkQuery = ""
    @FocusState private var typing: Bool
    /// The name "Save lens…" is asking for; nil while it is not asking.
    @State private var naming: String? = nil
    @FocusState private var typingName: Bool

    /// The tags the menu offers: the most used, up to this many.
    static let tagLimit = 8
    /// The buds "Linked to…" offers at once.
    static let linkLimit = 5

    var body: some View {
        let tags = store.tree.tagCounts().prefix(Self.tagLimit).map { LensFacet.tag($0.tag) }
        VStack(alignment: .leading, spacing: 2) {
            if !store.savedLenses.isEmpty { saved }
            section("Built in", LensFacet.builtIns)
            if !tags.isEmpty { section("Tags", Array(tags)) }
            let sources = Array(Self.sources(in: store.tree).prefix(Self.tagLimit))
            if !sources.isEmpty { section("Sources", sources) }
            links
            Divider().padding(.vertical, 4)
            footer
        }
        .padding(8)
        .frame(width: 300, alignment: .leading)
        // The name offered follows the rows; with none ticked there is nothing to name.
        .onChange(of: store.canvasFacets) { _, now in
            guard naming != nil else { return }
            naming = now.isEmpty ? nil : SavedLens.suggestedName(now.map(store.facetName))
        }
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

    /// The saved lenses by name; a tap asks a lens's question in place of the rows ticked, and
    /// the one the canvas asks now is marked. No counts: each would read the whole tree again
    /// on every change, and the footer counts the one asked.
    private var saved: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Saved")
                .textRole(.eyebrow)
                .foregroundStyle(Theme.text3)
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 2)
            ForEach(store.savedLenses) { lens in
                let on = store.canvasFacets.contains(.saved(lens))
                Button {
                    withAnimation(.easeOut(duration: 0.35)) { store.applyLens(lens.id) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: on ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            .foregroundStyle(on ? Theme.leaf : Theme.text2)
                            .frame(width: 16)
                        Text(lens.name)
                            .lineLimit(1)
                            .fontWeight(on ? .semibold : .regular)
                            .foregroundStyle(Theme.text)
                        Spacer(minLength: 8)
                    }
                    .textRole(.body)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(on ? Theme.leafSoft : .clear, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(lens.name)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    /// The sources the buds on the canvas came from, the most used first.
    static func sources(in tree: Tree) -> [LensFacet] {
        var counts: [String: Int] = [:]
        for bud in tree.walk(under: rootID) {
            if let key = LensQuery.sourceKey(bud.source) { counts[key, default: 0] += 1 }
        }
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map { .source($0.key) }
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
        var found: [(bud: Bud, count: Int)] = []
        for bud in canvas where !picked.contains(bud.id) {
            guard typed.isEmpty || BudLinks.fold(bud.text).contains(typed) else { continue }
            let count = store.links.around(bud.id).filter { onCanvas.contains($0.other) }.count
            if count > 0 { found.append((bud, count)) }
        }
        found.sort { a, b in a.count != b.count ? a.count > b.count : a.bud.text < b.bud.text }
        return Array(found.prefix(Self.linkLimit))
    }

    private func pick(_ bud: Bud) {
        withAnimation(.easeOut(duration: 0.35)) { store.canvasFacets.append(.linked(bud.id, title: bud.text)) }
        linking = false
        linkQuery = ""
    }

    private func row(_ facet: LensFacet) -> some View {
        let ticked = store.canvasFacets.contains(facet)
        let count = facet.query.hits(store.tree, links: store.links, on: store.now).count
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
        if let naming {
            nameField(naming)
        } else {
            HStack {
                if store.canvasFacets.isEmpty {
                    Text("Tick rows to light what matches")
                } else {
                    let hits = store.canvasLens?.hits(store.tree, links: store.links, on: store.now).count ?? 0
                    Text(Self.footerText(hits: hits, rows: store.canvasFacets.count))
                    Spacer()
                    if canSave {
                        Button("Save lens…") {
                            naming = SavedLens.suggestedName(store.canvasFacets.map(store.facetName))
                        }
                        .buttonStyle(.budGhost)
                        .accessibilityIdentifier("lens-save")
                    }
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
    }

    /// A lens is worth keeping while something is ticked, no saved lens asks the same, and the
    /// rows do not ask for two things nothing can be at once.
    private var canSave: Bool { SavedLens.refusal(query: store.canvasLens, saved: store.savedLenses) == nil }

    /// Why the lens cannot be kept under `name` now; nil when it can.
    private func refusal(_ name: String) -> String? {
        SavedLens.refusal(name: name, query: store.canvasLens, saved: store.savedLenses)
    }

    /// The name for the lens being kept, filled with the ticked rows' names; return keeps it.
    /// Why it cannot be kept, when it cannot, shows under it and Save waits.
    private func nameField(_ name: String) -> some View {
        let refused = refusal(name)
        return VStack(alignment: .leading, spacing: 4) {
            field(name, refused: refused)
            if let refused {
                Text(refused)
                    .textRole(.caption)
                    .foregroundStyle(Theme.text3)
                    .padding(.horizontal, 8)
            }
        }
    }

    private func field(_ name: String, refused: String?) -> some View {
        HStack(spacing: 6) {
            TextField("Name this lens", text: Binding(get: { naming ?? name }, set: { naming = $0 }))
                .textFieldStyle(.plain)
                .focused($typingName)
                .onSubmit(save)
                .accessibilityIdentifier("lens-save-name")
            Button("Save", action: save)
                .buttonStyle(.budGhost)
                .disabled(refused != nil)
            Button {
                naming = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Theme.text3)
                    .contentShape(Rectangle().inset(by: -6))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Stop naming the lens")
        }
        .textRole(.body)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).stroke(Theme.leafLine, lineWidth: 1))
        // A hop past the field's first frame, which a popover would otherwise drop.
        .task { typingName = true }
    }

    /// Asked again at the moment of saving: the rows or the saved lenses may have changed
    /// since the field opened.
    private func save() {
        guard let name = naming, refusal(name) == nil, store.saveLens(name) != nil else { return }
        naming = nil
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
