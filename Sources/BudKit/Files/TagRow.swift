#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// The tags under a page's title: plain chips, no colours. A tag of the bud's own list carries
/// ×; a `#tag` written in the body says "in text" and stays until the text changes. "+ Tag"
/// opens the picker.
struct TagRow: View {
    let bud: Bud
    @ObservedObject var store: BudStore
    @State private var picking = false

    var body: some View {
        WrapStack(spacing: 6) {
            ForEach(bud.tagChips, id: \.self) { chip in
                TagChipView(chip: chip) { store.removeTag(bud.id, chip.tag) }
            }
            Button { picking = true } label: {
                Label("Tag", systemImage: "plus")
                    .textRole(.label)
                    .foregroundStyle(Theme.leaf)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).stroke(Theme.leafLine, lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add a tag")
            .accessibilityIdentifier("add-tag")
            .popover(isPresented: $picking, arrowEdge: .bottom) {
                TagPicker(carried: bud.allTags, counts: store.tree.tagCounts()) { tag in
                    store.addTag(bud.id, tag)
                    picking = false
                }
                #if os(iOS)
                .presentationCompactAdaptation(.popover)
                #endif
            }
        }
    }
}

struct TagChipView: View {
    let chip: TagChip
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Text("#\(chip.tag)")
                .textRole(.label)
                .foregroundStyle(Theme.text2)
            if chip.inText {
                Text("in text")
                    .textRole(.caption)
                    .foregroundStyle(Theme.text3)
            } else {
                Button(action: remove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Theme.text3)
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove #\(chip.tag)")
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, chip.inText ? 8 : 4)
        .padding(.vertical, 3)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).stroke(Theme.line, lineWidth: 1))
        .accessibilityElement(children: chip.inText ? .combine : .contain)
    }
}

/// Searches the tags in use, in any case, each with its bud count, and offers to create what
/// is typed last. ↑↓ move, ↩ picks, Esc closes.
struct TagPicker: View {
    let carried: [String]
    let counts: [TagCount]
    let choose: (String) -> Void
    @State private var query: String
    @State private var pick = 0
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    init(carried: [String], counts: [TagCount], query: String = "", choose: @escaping (String) -> Void) {
        self.carried = carried
        self.counts = counts
        self.choose = choose
        _query = State(initialValue: query)
    }

    private var rows: [TagChoices.Row] { TagChoices.rows(for: query, in: counts, excluding: carried) }

    var body: some View {
        let rows = rows
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("#").foregroundStyle(Theme.text3)
                TextField("Tag", text: $query)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit { if rows.indices.contains(pick) { take(rows[pick]) } }
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
            }
            .textRole(.body)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).stroke(Theme.leafLine, lineWidth: 1))
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                Button { take(row) } label: { line(row, picked: index == pick) }
                    .buttonStyle(.plain)
            }
            if rows.isEmpty {
                Text(query.isEmpty ? "No tags yet. Type one." : "Not a tag: letters, digits, - _ and /.")
                    .textRole(.caption)
                    .foregroundStyle(Theme.text3)
                    .padding(8)
            }
        }
        .padding(6)
        .frame(width: 260, alignment: .leading)
        .onAppear { focused = true }
        .onChange(of: query) { _, _ in pick = 0 }
        .onKeyPress(.upArrow) { pick = max(0, pick - 1); return .handled }
        .onKeyPress(.downArrow) { pick = max(0, min(rows.count - 1, pick + 1)); return .handled }
        .onKeyPress(.escape) { dismiss(); return .handled }
        .accessibilityIdentifier("tag-picker")
    }

    private func take(_ row: TagChoices.Row) {
        switch row {
        case .tag(let count): choose(count.tag)
        case .create(let tag): choose(tag)
        }
    }

    @ViewBuilder private func line(_ row: TagChoices.Row, picked: Bool) -> some View {
        HStack(spacing: 8) {
            switch row {
            case .tag(let count):
                Text("#").foregroundStyle(Theme.text3)
                Text(count.tag)
                    .fontWeight(picked ? .semibold : .regular)
                    .foregroundStyle(Theme.text)
                Spacer(minLength: 8)
                Text(count.buds == 1 ? "1 bud" : "\(count.buds) buds")
                    .textRole(.caption)
                    .foregroundStyle(Theme.text3)
            case .create(let tag):
                Image(systemName: "plus").foregroundStyle(Theme.leaf)
                Text("Create #\(tag)").foregroundStyle(Theme.leaf)
                Spacer(minLength: 0)
            }
        }
        .textRole(.body)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(picked ? Theme.leafSoft : .clear, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .contentShape(Rectangle())
    }
}

/// Lays its views in rows, left to right, starting a new row when one is full.
struct WrapStack: SwiftUI.Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].items.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if extra > width, !rows[rows.count - 1].items.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.items.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.items.append(index)
            rows[rows.count - 1] = row
        }
        return rows.filter { !$0.items.isEmpty }
    }
}
#endif
