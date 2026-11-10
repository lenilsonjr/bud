#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// The keyboard shortcuts sheet (H2): every command grouped by scope, each with the key it
/// answers to now, read from the layout so a changed key shows at once. The system-wide keys sit
/// last in their own group, marked Mac. Esc closes it, and so does its own key.
///
/// A click on a keycap records (H3): the row's cap says so, the sheet takes the keyboard, and
/// the next key lands through the layout, which refuses a bare key where it would type and
/// holds a key another row has as a conflict on both rows (H4). A changed row carries a dot
/// and Reset; the footer counts the changes and offers Reset all.
struct ShortcutSheet: View {
    let close: () -> Void
    @Environment(\.compact) private var compact
    @ObservedObject private var layout = Keys.layout
    @FocusState private var listening: Bool
    /// The row the pointer is over, on the Mac, where Reset waits for it and the dot stays.
    @State private var hovered: Command.ID?

    /// How tall the list may grow before it scrolls.
    private static let listHeight: CGFloat = 480

    var body: some View {
        let groups = ShortcutText.groups()
        let halves = ShortcutText.halves(groups)
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
            // Sized to its rows up to the cap, so the card stays short where the rows are few.
            MaybeScroll {
                if compact {
                    column(groups)
                } else {
                    HStack(alignment: .top, spacing: 20) {
                        column(halves.0)
                        column(halves.1)
                    }
                }
            }
            .frame(maxHeight: Self.listHeight)
            .fixedSize(horizontal: false, vertical: true)
            if let count = ShortcutText.changed(layout.changed) {
                Theme.line.frame(height: 1)
                HStack(spacing: 8) {
                    Text(count)
                        .textRole(.caption)
                        .foregroundStyle(Theme.text3)
                    Spacer()
                    Button(ShortcutText.resetAll) { layout.resetAll() }
                        .buttonStyle(.plain)
                        .textRole(.label)
                        .foregroundStyle(Theme.leaf)
                }
            }
        }
        .textRole(.body)
        .tint(Theme.leaf)
        // The keys a row records come here: the sheet takes the keyboard while one records, as a
        // field would so Space and Return are keys and not a click, and lets go when it goes.
        .focusable(true, interactions: .edit)
        .focusEffectDisabled()
        .focused($listening)
        .onKeyPress(phases: .down) { press in
            guard layout.recording != nil else { return .ignored }
            if let key = Key(press) { layout.record(key) }
            return .handled
        }
        .onChange(of: layout.recording) { _, recording in listening = recording != nil }
        .onDisappear { layout.cancelRecording() }
        .background {
            // The cap in the head and this binding read the same row of the table; while a row
            // records, Esc is the recorder's.
            Button("", action: close)
                .keyboardShortcut(Keys.shortcut(.close))
                .disabled(layout.recording != nil)
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
        let recording = layout.recording == command.id
        let wants = layout.conflict?.id == command.id
        let holds = layout.conflict?.holder == command.id
        #if os(macOS)
        let offersReset = hovered == command.id
        #else
        let offersReset = true
        #endif
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(command.name)
                    .textRole(.body)
                    .foregroundStyle(Theme.text)
                Spacer(minLength: 8)
                if (layout.isChanged(command.id) || wants) && offersReset {
                    Button(ShortcutText.reset) { layout.reset(command.id) }
                        .buttonStyle(.plain)
                        .textRole(.caption)
                        .foregroundStyle(Theme.text3)
                }
                if layout.isChanged(command.id) {
                    Circle()
                        .fill(Theme.pistil)
                        .frame(width: 6, height: 6)
                }
                Button { layout.startRecording(command.id) } label: {
                    if recording {
                        Keycap(ShortcutText.recording, look: .sheet, tone: .live)
                    } else if wants, let conflict = layout.conflict {
                        Keycap(conflict.key, look: .sheet, tone: .taken)
                    } else {
                        Keycap(layout.key(for: command.id), look: .sheet, tone: holds ? .taken : .plain)
                    }
                }
                .buttonStyle(.plain)
            }
            if let line = hint(for: command) {
                Text(line)
                    .textRole(.caption)
                    .foregroundStyle(recording ? Theme.text3 : Theme.rose)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        #if os(macOS)
        .onHover { over in
            if over { hovered = command.id } else if hovered == command.id { hovered = nil }
        }
        #endif
    }

    /// The line under a row: how to stop while it records, why its key did not land, or which
    /// row wants the key it holds.
    private func hint(for command: Command) -> String? {
        if layout.recording == command.id {
            return layout.refused ? ShortcutText.bareKeyRefused : ShortcutText.recordingHint
        }
        guard let conflict = layout.conflict else { return nil }
        if conflict.id == command.id { return ShortcutText.taken(by: Command.of(conflict.holder), key: conflict.key) }
        if conflict.holder == command.id { return ShortcutText.wanted(by: Command.of(conflict.id)) }
        return nil
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
