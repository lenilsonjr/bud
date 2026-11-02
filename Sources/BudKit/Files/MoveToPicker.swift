#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// Move to…: a search field over Everything and every bud. Return moves to the picked row, and so
/// does a click; the arrows move the pick, Esc cancels.
struct MoveToPicker: View {
    @ObservedObject var store: BudStore
    let bud: Bud
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var picked = 0
    @FocusState private var typing: Bool

    private var targets: [SearchHit] {
        MoveTargets(tree: store.tree).matching(query, for: bud.id)
    }

    var body: some View {
        let targets = targets
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Move to…")
                    .textRole(.heading)
                    .foregroundStyle(Theme.text)
                Text(bud.text)
                    .textRole(.caption)
                    .lineLimit(1)
                    .foregroundStyle(Theme.text3)
            }
            .padding(.bottom, 12)
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.text3)
                TextField("Search every bud", text: $query)
                    .textFieldStyle(.plain)
                    .textRole(.body)
                    .foregroundStyle(Theme.text)
                    .focused($typing)
                    .onSubmit { go(targets) }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).stroke(typing ? Theme.leafLine : Theme.line, lineWidth: 1))
            .padding(.bottom, 8)
            ScrollViewReader { proxy in
                MaybeScroll {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(targets.enumerated()), id: \.offset) { index, hit in
                            line(hit, picked: index == picked)
                                .id(index)
                                .onTapGesture {
                                    picked = index
                                    go(targets)
                                }
                        }
                        if targets.isEmpty {
                            Text("Nothing matches.")
                                .textRole(.body)
                                .foregroundStyle(Theme.text3)
                                .padding(10)
                        }
                    }
                }
                .frame(height: 260)
                .onChange(of: picked) { _, now in proxy.scrollTo(now) }
            }
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Text("↵ move here · ↑↓ pick · esc cancel")
                    .textRole(.caption)
                    .foregroundStyle(Theme.text3)
            }
            .padding(.top, 12)
        }
        .padding(20)
        .frame(minWidth: 420)
        .textRole(.body)
        .background(Theme.surface)
        .tint(Theme.leaf)
        .onAppear { typing = true }
        .onChange(of: query) { _, _ in picked = 0 }
        .onKeyPress(.downArrow) { step(1, in: targets.count); return .handled }
        .onKeyPress(.upArrow) { step(-1, in: targets.count); return .handled }
    }

    private func line(_ hit: SearchHit, picked: Bool) -> some View {
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(picked ? Theme.leafSoft : .clear, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .contentShape(Rectangle())
    }

    private func step(_ by: Int, in count: Int) {
        guard count > 0 else { return }
        picked = (picked + by + count) % count
    }

    private func go(_ targets: [SearchHit]) {
        guard targets.indices.contains(picked) else { return }
        store.move(bud.id, under: targets[picked].id)
        dismiss()
    }
}
#endif
