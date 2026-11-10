#if canImport(SwiftUI) && os(macOS)
import SwiftUI

/// The face of Go anywhere from the desktop: the same palette as the window's, in a floating
/// panel over whatever app is in front. Typing filters as inside the app; Return goes to the row
/// chosen and brings the app forward, ⌘Return opens it in Files; Esc closes the panel and leaves
/// the front app where it was. The AppKit panel around it lives in the app.
public struct DesktopPaletteView: View {
    @ObservedObject var store: BudStore
    let onGo: () -> Void
    let onClose: () -> Void

    /// How much room the panel gives the palette: its width, and the list's height with the
    /// query and the footer.
    public static let size = CGSize(width: 560, height: 470)

    public init(store: BudStore, onGo: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.store = store
        self.onGo = onGo
        self.onClose = onClose
    }

    public var body: some View {
        CommandPalette(store: store, onClose: onClose, onGo: onGo)
            .frame(width: Self.size.width, height: Self.size.height, alignment: .top)
            .textRole(.body)
            .foregroundStyle(Theme.text)
            .tint(Theme.leaf)
            .onExitCommand(perform: onClose)
    }
}
#endif
