#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// Go anywhere: a query, the buds that match with their trail, the places and lenses, and the
/// keys in the footer. Return centers the pick on the canvas, ⌘Return opens it in Files.
struct CommandPalette: View {
    @Environment(\.keys) private var keys
    @ObservedObject var store: BudStore
    /// In a phone sheet: the sheet draws the card, and the list takes what height it has.
    var inSheet = false
    let onClose: () -> Void
    /// What follows a row chosen, when that is more than closing: the desktop panel brings the
    /// app forward. Esc only ever closes.
    var onGo: (() -> Void)? = nil
    @State private var query = ""
    @State private var picked = 0
    @FocusState private var typing: Bool
    @Environment(\.compact) private var compact

    private enum Row: Hashable {
        case bud(SearchHit)
        case destination(Destination)
    }

    /// On a phone a tap goes where you are: Files selects the hit, the canvas centers it.
    private var tapOpensInFiles: Bool { compact && store.surface == .files }

    private var browsing: Bool { query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// With a query, the buds that match and then the places; with none, the places and lenses
    /// and then the recent buds.
    private var rows: [Row] {
        let hits = TreeSearcher(tree: store.tree).search(query, limit: 30).map(Row.bud)
        let places = Destination.matching(query).map(Row.destination)
        return browsing ? places + hits : hits + places
    }

    /// The row to start on: the first bud, so Return goes somewhere specific.
    private func firstPick(in rows: [Row]) -> Int {
        rows.firstIndex { if case .bud = $0 { return true } else { return false } } ?? 0
    }

    var body: some View {
        let rows = rows
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.text3)
                TextField("Go anywhere", text: $query)
                    .textFieldStyle(.plain)
                    .textRole(.heading)
                    .foregroundStyle(Theme.text)
                    .focused($typing)
                if compact {
                    Button("Cancel", action: onClose)
                        .buttonStyle(.budGhost)
                } else {
                    Keycap(keys.key(for: .close).label)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Theme.line.frame(height: 1)
            ScrollViewReader { proxy in
                MaybeScroll {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                            if index == 0 || heading(rows[index - 1]) != heading(row) {
                                Text(heading(row).uppercased())
                                    .textRole(.eyebrow)
                                    .foregroundStyle(Theme.text3)
                                    .padding(.horizontal, 16)
                                    .padding(.top, index == 0 ? 10 : 14)
                                    .padding(.bottom, 4)
                            }
                            line(row, picked: index == picked)
                                .id(index)
                                .onTapGesture {
                                    picked = index
                                    // On a phone a tap goes where you are; on the Mac the keys say.
                                    go(rows, inFiles: tapOpensInFiles)
                                }
                                .contextMenu {
                                    if compact, case .bud = row {
                                        Button(PhonePalette.otherWay(inFiles: tapOpensInFiles)) {
                                            picked = index
                                            go(rows, inFiles: !tapOpensInFiles)
                                        }
                                    }
                                }
                        }
                        if rows.isEmpty {
                            Text("Nothing matches.")
                                .textRole(.body)
                                .foregroundStyle(Theme.text3)
                                .padding(16)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 8)
                }
                .frame(maxHeight: inSheet ? .infinity : (compact ? 300 : 360), alignment: .top)
                .clipped()
                .onChange(of: picked) { _, now in proxy.scrollTo(now) }
            }
            if !compact {
                Theme.line.frame(height: 1)
                Text(Self.footer)
                    .textRole(.caption)
                    .foregroundStyle(Theme.text3)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: inSheet ? .infinity : 560)
        .background(inSheet ? .clear : Theme.raised, in: RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous).stroke(inSheet ? .clear : Theme.line, lineWidth: 1))
        .shadow(color: inSheet ? .clear : Theme.shadowStrong, radius: inSheet ? 0 : 24, y: inSheet ? 0 : 12)
        .onAppear { typing = true; picked = firstPick(in: rows) }
        .onChange(of: query) { _, _ in picked = firstPick(in: self.rows) }
        .onKey(.rowDown) { _ in move(1, in: rows.count); return .handled }
        .onKey(.rowUp) { _ in move(-1, in: rows.count); return .handled }
        .onKey(.close) { _ in onClose(); return .handled }
        .onKey(.choose, phases: .down) { press in
            go(rows, inFiles: press.modifiers.isSuperset(of: keys.modifiers(.openInFiles)))
            return .handled
        }
    }

    /// The keys in the footer, read off the table.
    static var footer: String {
        let key = { (id: Command.ID) in keys.key(for: id).label }
        return "\(key(.choose)) center on canvas · \(key(.openInFiles)) open in Files · \(key(.rowUp))\(key(.rowDown)) move · \(key(.close)) back"
    }

    private func heading(_ row: Row) -> String {
        switch row {
        case .bud: return browsing ? "Recent" : "Buds"
        case .destination(let d): return d.isPlace ? "Places" : "Lenses"
        }
    }

    private func line(_ row: Row, picked: Bool) -> some View {
        HStack(spacing: 10) {
            switch row {
            case .bud(let hit):
                if let bud = store.tree.bud(hit.id) {
                    RowMark(bud: bud)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(hit.title)
                        .textRole(.body)
                        .lineLimit(1)
                        .foregroundStyle(Theme.text)
                    if !hit.trail.isEmpty {
                        Text(hit.trailText)
                            .textRole(.caption)
                            .lineLimit(1)
                            .foregroundStyle(Theme.text3)
                    }
                }
            case .destination(let d):
                Image(systemName: glyph(d))
                    .frame(width: 14)
                    .foregroundStyle(Theme.text2)
                Text(d.rawValue)
                    .textRole(.body)
                    .foregroundStyle(Theme.text)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(picked ? Theme.leafSoft : .clear, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .contentShape(Rectangle())
    }

    private func glyph(_ d: Destination) -> String {
        switch d {
        case .inbox: return "tray"
        case .everything: return "leaf.fill"
        case .archive: return "archivebox"
        case .trash: return "trash"
        case .today: return "sun.max"
        case .todos: return "checkmark.square"
        case .pinned: return "pin"
        }
    }

    private func move(_ by: Int, in count: Int) {
        guard count > 0 else { return }
        picked = (picked + by + count) % count
    }

    private func go(_ rows: [Row], inFiles: Bool) {
        guard rows.indices.contains(picked) else { return }
        let pick: BudStore.Pick
        switch rows[picked] {
        case .bud(let hit): pick = .bud(hit.id)
        case .destination(let d): pick = .destination(d)
        }
        withAnimation(.spring(duration: 0.8, bounce: 0.12)) { store.go(pick, inFiles: inFiles) }
        (onGo ?? onClose)()
    }
}
#endif
