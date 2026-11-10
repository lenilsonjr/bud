#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// The keyboard shortcuts sheet (H2): every command grouped by scope, each with the key it
/// answers to now, read from the table so a changed key shows at once. The system-wide keys sit
/// last in their own group, marked Mac. Esc closes it, and so does its own key.
struct ShortcutSheet: View {
    let close: () -> Void
    @Environment(\.compact) private var compact

    private let groups = ShortcutText.groups()
    private var halves: ([ShortcutText.Group], [ShortcutText.Group]) { ShortcutText.halves(groups) }

    init(close: @escaping () -> Void) {
        self.close = close
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ShortcutText.title)
                        .textRole(.heading)
                        .foregroundStyle(Theme.text)
                    Text(ShortcutText.note)
                        .textRole(.caption)
                        .foregroundStyle(Theme.text3)
                }
                Spacer()
                #if os(macOS)
                Keycap(Keys.key(for: .close))
                #endif
            }
            Theme.line.frame(height: 1)
            if compact {
                column(groups)
            } else {
                HStack(alignment: .top, spacing: 20) {
                    column(halves.0)
                    column(halves.1)
                }
            }
        }
        .textRole(.body)
        .tint(Theme.leaf)
        .background {
            Button("", action: close)
                .keyboardShortcut(.cancelAction)
                .opacity(0)
        }
    }

    private func column(_ groups: [ShortcutText.Group]) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(groups, id: \.title) { group in
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.title.uppercased())
                        .textRole(.eyebrow)
                        .foregroundStyle(Theme.text3)
                    if let caption = group.caption {
                        Text(caption)
                            .textRole(.caption)
                            .foregroundStyle(Theme.text3)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 14)
                .padding(.bottom, 6)
                ForEach(group.commands) { command in
                    row(command)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ command: Command) -> some View {
        HStack(spacing: 8) {
            Text(command.name)
                .textRole(.body)
                .foregroundStyle(Theme.text)
            Spacer(minLength: 8)
            Keycap(Keys.key(for: command.id), look: .sheet)
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 5)
    }
}

#if os(macOS)
/// The round question mark at the bottom right of the window (H1), over the canvas and Files
/// alike: it opens the sheet, and its tooltip names the key that does the same.
struct HelpButton: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text("?")
                .font(Theme.font(TextStyle(typeface: .display, size: 19, weight: hovered ? 600 : 500)))
                .foregroundStyle(hovered ? Theme.leaf : Theme.text2)
                .frame(width: 36, height: 36)
                .background(hovered ? Theme.raised : Theme.glass, in: Circle())
                .overlay(Circle().stroke(hovered ? Theme.leafLine : Theme.lineStrong, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help("\(ShortcutText.title) \(Keys.key(for: .shortcuts).label)")
        .accessibilityLabel(ShortcutText.title)
    }
}
#endif
#endif
