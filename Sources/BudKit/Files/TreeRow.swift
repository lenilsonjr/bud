#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// One bud in the sidebar tree: indented by depth, a disclosure when it has children, the kind
/// mark, the title, and the count of what it holds on the right.
struct TreeRow: View {
    let bud: Bud
    let tree: Tree
    let depth: Int
    let selected: Bool
    let expanded: Bool
    let onSelect: () -> Void
    let onDisclose: () -> Void

    var body: some View {
        let kids = tree.children(of: bud.id).count
        HStack(spacing: 6) {
            Group {
                if kids > 0 {
                    Button(action: onDisclose) {
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                            .textRole(.caption)
                            .foregroundStyle(Theme.text3)
                            .frame(width: 14, height: 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear.frame(width: 14, height: 14)
                }
            }
            KindMark(bud: bud, style: CardStyle.chip(for: bud, lit: false))
                .frame(width: 14)
            Text(bud.text)
                .textRole(.body)
                .lineLimit(1)
                .strikethrough(bud.isDone)
                .foregroundStyle(bud.isDone ? Theme.text3 : Theme.text)
            Spacer(minLength: 4)
            if kids > 0 {
                Text("\(kids)")
                    .textRole(.caption)
                    .foregroundStyle(Theme.text3)
            }
        }
        .padding(.leading, 8 + CGFloat(depth + 1) * 14)
        .padding(.trailing, 8)
        .padding(.vertical, 4)
        .background(selected ? Theme.leafSoft : .clear, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}
#endif
