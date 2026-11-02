#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// A segmented switch drawn in SwiftUI, so it looks the same on every platform and in pictures.
struct Segmented<Option: Hashable>: View {
    @Binding var selection: Option
    let options: [Option]
    let label: (Option) -> String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let on = option == selection
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { selection = option }
                } label: {
                    Text(label(option))
                        .textRole(.label)
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(on ? Theme.text : Theme.text2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                .fill(on ? Theme.raised : .clear)
                                .shadow(color: .black.opacity(on ? 0.08 : 0), radius: 1, y: 1)
                                .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).stroke(on ? Theme.lineStrong : .clear, lineWidth: 1))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Theme.sidebar, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Theme.line, lineWidth: 1))
    }
}
#endif
