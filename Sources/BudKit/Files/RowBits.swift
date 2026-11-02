#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// The lead slot of a row: the box of a to-do (a click ticks it) or the dot of a note, in one
/// fixed frame, so titles start on the same column whatever the marker.
struct RowMark: View {
    let bud: Bud
    let onTick: (() -> Void)?

    init(bud: Bud, onTick: (() -> Void)? = nil) {
        self.bud = bud
        self.onTick = onTick
    }

    var body: some View {
        Group {
            if bud.isTodo {
                if let onTick {
                    Button(action: onTick) {
                        KindMark(bud: bud, style: CardStyle.chip(for: bud, lit: false))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    KindMark(bud: bud, style: CardStyle.chip(for: bud, lit: false))
                }
            } else {
                Circle()
                    .fill(Theme.leaf)
                    .frame(width: 6, height: 6)
            }
        }
        .frame(width: 16, height: 18)
    }
}

/// A date the way the Today lens shows it: "Due 3 Nov" in pistil on a pistil wash.
struct DateTag: View {
    let label: String
    let date: Date

    var body: some View {
        Text("\(label) \(date.formatted(date: .abbreviated, time: .omitted))")
            .textRole(.label)
            .foregroundStyle(Theme.pistil)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.pistilSoft, in: Capsule())
    }
}

/// The neutral tag: "raw", "3 inside". Raised fill, radius 5, 11 pt semibold, one minimum
/// width so a column of them lines up.
struct NeutralTag: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Theme.font(TextStyle(typeface: .text, size: 11, weight: 600)))
            .foregroundStyle(Theme.text2)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .frame(minWidth: 56)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).stroke(Theme.line, lineWidth: 1))
    }
}

/// The page column: 760 wide, centred in the main area, as the design draws every page.
struct PageColumn: ViewModifier {
    @Environment(\.compact) private var compact

    func body(content: Content) -> some View {
        content
            .padding(compact ? 16 : 28)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
    }
}

extension View {
    func pageColumn() -> some View { modifier(PageColumn()) }

    /// The 1 pt line under a list row.
    func rowHairline() -> some View {
        overlay(alignment: .bottom) { Theme.line.frame(height: 1) }
    }
}
#endif
