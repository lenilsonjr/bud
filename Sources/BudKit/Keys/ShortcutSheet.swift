#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// The keyboard shortcuts sheet (H2): every command grouped by scope, each with the key it
/// answers to now, read from the layout so a changed key shows at once. The system-wide keys sit
/// last in their own group, marked Mac. Esc closes it, and so does its own key.
///
/// A click on a keycap records (H3): the row's cap says so, the sheet takes the keyboard, and
/// the next key lands through the layout, which refuses a bare key where it would type and
/// holds a key another row has as a conflict on both rows (H4). A changed row carries a dot
/// and Reset; the footer counts the changes and offers Reset all. The keys the Mac answers to
/// from the desktop record by the key's place on the keyboard, on the Mac alone, and show as
/// taken when the system keeps the key for itself or another app.
struct ShortcutSheet: View {
    /// The layout the rows read and record into: the store's, so a picture can bring its own.
    @ObservedObject var layout: KeyLayout
    let close: () -> Void
    @Environment(\.compact) private var compact
    @FocusState private var listening: Bool
    /// The row the pointer is over, on the Mac, where Reset waits for it and the dot stays.
    @State private var hovered: Command.ID?
    #if os(macOS)
    /// The ear on the key events while a row records.
    @State private var monitor: Any?
    #endif

    /// How tall the list may grow before it scrolls.
    private static let listHeight: CGFloat = 480
    /// How long the line for a key the table cannot name stays.
    private static let refusalBeat: Duration = .seconds(2)

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
                Keycap(layout.key(for: .close))
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
        // field would so Space and Return are keys and not a click, and lets go when it goes. On
        // the Mac the event itself is read, before any view or menu row answers it.
        .focusable(true, interactions: .edit)
        .focusEffectDisabled()
        .focused($listening)
        #if !os(macOS)
        .onKeyPress(phases: .down) { press in
            guard layout.recording != nil else { return .ignored }
            layout.record(Key(press))
            return .handled
        }
        #endif
        .onChange(of: layout.recording) { _, recording in
            listening = recording != nil
            #if os(macOS)
            listen(recording != nil)
            #endif
        }
        .onDisappear {
            layout.cancelRecording()
            #if os(macOS)
            listen(false)
            #endif
        }
        // A key the table cannot name is said so for a beat, the row still recording.
        .task(id: layout.refusal) {
            guard layout.refusal == .unnamed else { return }
            do { try await Task.sleep(for: Self.refusalBeat) } catch { return }
            layout.clearRefusal()
        }
        .background {
            // The cap in the head and this binding read the same row of the table; while a row
            // records, Esc is the recorder's.
            Button("", action: close)
                .keyboardShortcut(layout.recording == nil ? layout.key(for: .close).shortcut : nil)
                .opacity(0)
        }
    }

    #if os(macOS)
    /// Hears the key for the row recording before any view or menu does, so what Option makes
    /// of a key and a key a menu row holds both reach the recorder, and nothing else answers.
    private func listen(_ recording: Bool) {
        if recording, monitor == nil {
            let layout = layout
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                layout.record(Key(event), at: event.keyCode)
                return nil
            }
        } else if !recording, let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
    #endif

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
        let wants = layout.conflicts[command.id]
        let holds = layout.wanted(command.id)
        let refused = layout.isTakenBySystem(command.id)
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
                if (layout.isChanged(command.id) || wants != nil) && offersReset {
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
                if layout.canRecord(command.id) {
                    Button { layout.startRecording(command.id) } label: {
                        cap(command, recording: recording, wants: wants, taken: holds != nil || refused)
                    }
                    .buttonStyle(.plain)
                } else {
                    cap(command, recording: false, wants: nil, taken: false)
                }
            }
            if let line = hint(for: command, recording: recording, wants: wants, holds: holds, refused: refused) {
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

    /// The row's keycap: the key it answers to, the recorder's word while it records, or the
    /// key it wants that another row holds. A key another row wants, or the system keeps, reads
    /// as taken.
    @ViewBuilder private func cap(_ command: Command, recording: Bool, wants: KeyLayout.Conflict?, taken: Bool) -> some View {
        if recording {
            Keycap(ShortcutText.recording, look: .sheet, tone: .live)
        } else if let wants {
            Keycap(wants.key, look: .sheet, tone: .taken)
        } else {
            Keycap(layout.key(for: command.id), look: .sheet, tone: taken ? .taken : .plain)
        }
    }

    /// The line under a row: how to stop while it records, why its key did not land, which
    /// row wants the key it holds, or that the system would not give the app the key.
    private func hint(for command: Command, recording: Bool, wants: KeyLayout.Conflict?, holds: KeyLayout.Conflict?, refused: Bool) -> String? {
        if recording {
            switch layout.refusal {
            case .bare: return ShortcutText.bareKeyRefused
            case .unnamed: return ShortcutText.unnamedKey
            case nil: return ShortcutText.recordingHint
            }
        }
        if let wants { return ShortcutText.taken(by: Command.of(wants.holder), key: wants.key) }
        if let holds { return ShortcutText.wanted(by: Command.of(holds.id)) }
        if refused { return ShortcutText.takenBySystem }
        return nil
    }
}

#if os(macOS)
/// The round question mark at the bottom right of the window (H1), over the canvas and Files
/// alike: it opens the sheet, and its tooltip names the key that does the same.
struct HelpButton: View {
    let action: () -> Void
    @Environment(\.keys) private var keys
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
        .help("\(ShortcutText.title) \(keys.key(for: .shortcuts).label)")
        .accessibilityLabel(ShortcutText.title)
    }
}
#endif
#endif
