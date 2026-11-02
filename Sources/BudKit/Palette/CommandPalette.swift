#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// Go anywhere: a query, the buds that match with their trail, the places and lenses, and the
/// keys in the footer. Return centers the pick on the canvas, ⌘Return opens it in Files.
struct CommandPalette: View {
    @ObservedObject var store: BudStore
    let onClose: () -> Void
    @State private var query = ""
    @State private var picked = 0
    @FocusState private var typing: Bool

    private enum Row: Hashable {
        case bud(SearchHit)
        case destination(Destination)
    }

    private var rows: [Row] {
        let hits = TreeSearcher(tree: store.tree).search(query, limit: 30).map(Row.bud)
        let places = Destination.matching(query).map(Row.destination)
        return hits + places
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
                Keycap("esc")
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
                                    go(rows, inFiles: false)
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
                .frame(maxHeight: 360)
                .onChange(of: picked) { _, now in proxy.scrollTo(now) }
            }
            Theme.line.frame(height: 1)
            Text("↵ center on canvas · ⌘↵ open in Files · ↑↓ move · esc back")
                .textRole(.caption)
                .foregroundStyle(Theme.text3)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .frame(width: 560)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Theme.line, lineWidth: 1))
        .shadow(color: Theme.shadowStrong, radius: 24, y: 12)
        .onAppear { typing = true }
        .onChange(of: query) { _, _ in picked = 0 }
        .onKeyPress(.downArrow) { move(1, in: rows.count); return .handled }
        .onKeyPress(.upArrow) { move(-1, in: rows.count); return .handled }
        .onKeyPress(.escape) { onClose(); return .handled }
        .onKeyPress(.return, phases: .down) { press in
            go(rows, inFiles: press.modifiers.contains(.command))
            return .handled
        }
    }

    private func heading(_ row: Row) -> String {
        switch row {
        case .bud: return "Buds"
        case .destination(let d): return d.isPlace ? "Places" : "Lenses"
        }
    }

    private func line(_ row: Row, picked: Bool) -> some View {
        HStack(spacing: 10) {
            switch row {
            case .bud(let hit):
                if let bud = store.tree.bud(hit.id) {
                    KindMark(bud: bud, style: CardStyle.chip(for: bud, lit: false)).frame(width: 14)
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
        switch rows[picked] {
        case .bud(let hit):
            if inFiles {
                store.openAsFile(hit.id)
            } else {
                withAnimation(.spring(duration: 0.8, bounce: 0.12)) { store.center = hit.id }
                store.surface = .canvas
            }
        case .destination(let d):
            // Inbox and Archive wait for the vault.
            switch d {
            case .everything:
                withAnimation(.spring(duration: 0.8, bounce: 0.12)) { store.center = rootID }
                if inFiles { store.surface = .files }
            case .today: store.open(.today)
            case .todos: store.open(.todos)
            case .pinned: store.open(.pinned)
            case .inbox, .archive: break
            }
        }
        onClose()
    }
}
#endif
