#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// A key the way the board draws it: a small rounded tile with the shortcut in it. Inline it is
/// a hint beside a control; on the sheet it is a raised key with a heavier bottom edge.
struct Keycap: View {
    enum Look {
        case inline, sheet
    }

    /// How the sheet's key reads: as it is, live while the row records, or as one two rows want.
    enum Tone {
        case plain, live, taken
    }

    let text: String
    let look: Look
    let tone: Tone

    init(_ text: String, look: Look = .inline, tone: Tone = .plain) {
        self.text = text
        self.look = look
        self.tone = tone
    }

    init(_ key: Key, look: Look = .inline, tone: Tone = .plain) {
        self.init(key.label, look: look, tone: tone)
    }

    private var ink: Color {
        switch tone {
        case .plain: return Theme.text2
        case .live: return Theme.leaf
        case .taken: return Theme.rose
        }
    }

    private var edge: Color {
        switch tone {
        case .plain, .taken: return Theme.lineStrong
        case .live: return Theme.leafLine
        }
    }

    private static let sheetShape = RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)

    var body: some View {
        switch look {
        case .inline:
            Text(text)
                .font(Theme.font(TextStyle(typeface: .mono, size: 10, weight: 500)))
                .foregroundStyle(Theme.text3)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .overlay(RoundedRectangle(cornerRadius: Radius.keycap, style: .continuous).stroke(Theme.lineStrong, lineWidth: 1))
        case .sheet:
            Text(text)
                .font(Theme.font(TextStyle(typeface: .mono, size: 12, weight: 500)))
                .foregroundStyle(ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Theme.raised, in: Self.sheetShape)
                .background(Self.sheetShape.fill(edge).offset(y: 1))
                .overlay(Self.sheetShape.stroke(edge, lineWidth: 1))
        }
    }
}
#endif
