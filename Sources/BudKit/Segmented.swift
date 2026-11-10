#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// A segmented switch drawn in SwiftUI, so it looks the same on every platform and in pictures.
struct Segmented<Option: Hashable>: View {
    @Binding var selection: Option
    let options: [Option]
    /// A small symbol before a segment's word, for the few that carry one; nil for none.
    var icon: (Option) -> String? = { _ in nil }
    let label: (Option) -> String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let on = option == selection
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { selection = option }
                } label: {
                    HStack(spacing: 5) {
                        if let symbol = icon(option) {
                            Image(systemName: symbol)
                                .textRole(.caption)
                                .foregroundStyle(on ? Theme.leaf : Theme.text3)
                                .accessibilityHidden(true)
                        }
                        Text(label(option))
                            .textRole(.label)
                            .lineLimit(1)
                            .fixedSize()
                            .foregroundStyle(on ? Theme.text : Theme.text2)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .raisedSegment(on: on)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label(option))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Theme.sidebar, in: RoundedRectangle(cornerRadius: Radius.segmented, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.segmented, style: .continuous).stroke(Theme.line, lineWidth: 1))
    }
}

/// The lit segment's chrome: raised, a strong line and a hair of shadow; off, none of it. The
/// switch's segments and the folded switch in a narrow bar share it, so one reads as the other.
/// The shadow is the switch's own, lighter than the board's shadow token, which would weigh
/// five times as much in the dark under a chrome this small.
struct RaisedSegment: ViewModifier {
    var on = true

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
        content
            .background(shape.fill(on ? Theme.raised : .clear).shadow(color: .black.opacity(on ? 0.08 : 0), radius: 1, y: 1))
            .overlay(shape.stroke(on ? Theme.lineStrong : .clear, lineWidth: 1))
            .contentShape(Rectangle())
    }
}

extension View {
    func raisedSegment(on: Bool = true) -> some View { modifier(RaisedSegment(on: on)) }
}
#endif
