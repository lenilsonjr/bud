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
            RowMark(bud: bud)
            title(kids: kids)
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
        .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).stroke(selected ? Theme.leafLine : .clear, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }

    /// With a count on the right a long title fades out under it instead of ending in an
    /// ellipsis; a leaf's title truncates as usual.
    @ViewBuilder private func title(kids: Int) -> some View {
        let text = Text(bud.text)
            .textRole(.body)
            .lineLimit(1)
            .strikethrough(bud.isDone)
            .foregroundStyle(bud.isDone ? Theme.text3 : Theme.text)
        if kids > 0 {
            FadingTitle(text: text)
        } else {
            text
        }
    }
}

/// A title that is drawn whole while it fits and fades out only where it would run under the
/// count beside it.
private struct FadingTitle<Label: View>: View {
    let text: Label
    @State private var textWidth: CGFloat = 0
    @State private var availableWidth: CGFloat = 0

    var body: some View {
        text
            .fixedSize(horizontal: true, vertical: false)
            .background(GeometryReader { proxy in
                Color.clear.onAppear { textWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, width in textWidth = width }
            })
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GeometryReader { proxy in
                Color.clear.onAppear { availableWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, width in availableWidth = width }
            })
            .clipped()
            .mask(fade)
    }

    private var fade: LinearGradient {
        let fades = TitleFade.needsFade(textWidth: textWidth, availableWidth: availableWidth)
        return LinearGradient(
            stops: [.init(color: .black, location: 0), .init(color: .black, location: fades ? 0.85 : 1), .init(color: fades ? .clear : .black, location: 1)],
            startPoint: .leading, endPoint: .trailing)
    }
}
#endif
