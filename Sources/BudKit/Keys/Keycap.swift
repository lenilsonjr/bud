#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// A key the way the board draws it: a small rounded tile with the shortcut in it. Inline it is
/// a hint beside a control; on the sheet it is a raised key with a heavier bottom edge.
struct Keycap: View {
    enum Look {
        case inline, sheet
    }

    let text: String
    let look: Look

    init(_ text: String, look: Look = .inline) {
        self.text = text
        self.look = look
    }

    init(_ key: Key, look: Look = .inline) {
        self.init(key.label, look: look)
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
                .foregroundStyle(Theme.text2)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Theme.raised, in: Self.sheetShape)
                .background(Self.sheetShape.fill(Theme.lineStrong).offset(y: 1))
                .overlay(Self.sheetShape.stroke(Theme.lineStrong, lineWidth: 1))
        }
    }
}
#endif
