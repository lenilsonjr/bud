#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// The draft of a new child under the lit card: a dashed card with "New bud". One click turns it
/// into the inline bar.
struct InlineAddDraft: View {
    let onTap: () -> Void
    let onHover: (Bool) -> Void

    var body: some View {
        Label("New bud", systemImage: "plus")
            .textRole(.label)
            .foregroundStyle(Theme.text3)
            .frame(width: 150, height: 32)
            .background(Theme.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Theme.lineStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .contentShape(RoundedRectangle(cornerRadius: Radius.card))
            .onTapGesture(perform: onTap)
            .onHover(perform: onHover)
            .accessibilityLabel("New bud")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("inline-add-draft")
    }
}

/// The inline bar: a kind switch and one line. Return plants and keeps the bar for the next line,
/// Tab goes down into the bud just planted, Shift-Tab comes back up, Escape closes.
struct InlineAddBar: View {
    @Environment(\.keys) private var keys
    static let width: CGFloat = 320
    private static let backtab = KeyEquivalent("\u{19}")

    @Binding var bar: InlineAdd
    var typing: FocusState<Bool>.Binding
    let placeholder: String
    let onSubmit: () -> Void
    let onNest: () -> Void
    let onRise: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button { bar.todo.toggle() } label: {
                Label(bar.todo ? "To-do" : "Note", systemImage: bar.todo ? "checkmark.square" : "text.alignleft")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(bar.todo ? Theme.leaf : Theme.text2)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(bar.todo ? "To-do: switch to a note" : "Note: switch to a to-do")
            .accessibilityLabel(bar.todo ? "Switch to note" : "Switch to to-do")
            .accessibilityValue(bar.todo ? "To-do" : "Note")
            .accessibilityIdentifier("inline-add-kind")
            TextField(placeholder, text: $bar.text)
                .textFieldStyle(.plain)
                .textRole(.body)
                .foregroundStyle(Theme.text)
                .focused(typing)
                .accessibilityIdentifier("inline-add-line")
                .submitLabel(.next)
                .onSubmit {
                    onSubmit()
                    // On iPhone Return lets the keyboard go; the line asks for it back next turn.
                    DispatchQueue.main.async { typing.wrappedValue = true }
                }
                // Shift-Tab arrives as a backtab on some keyboards, so the bar listens for both.
                .onKeyPress(keys: [keys.equivalent(.nest), Self.backtab]) { press in
                    if press.modifiers.isSuperset(of: keys.modifiers(.rise)) || press.key == Self.backtab { onRise() } else { onNest() }
                    return .handled
                }
                .onKey(.close) { _ in
                    onClose()
                    return .handled
                }
            if bar.canRise {
                icon("arrow.up.left", label: "Back up a level", help: "Back up a level (Shift-Tab)", id: "inline-add-rise", action: onRise)
            }
            if bar.canNest {
                icon("arrow.turn.down.right", label: "Add inside the last one", help: "Add inside the last one (Tab)", id: "inline-add-nest", action: onNest)
            }
            icon("xmark", label: "Done adding", help: "Done adding (Esc)", id: "inline-add-close", action: onClose)
        }
        .padding(.horizontal, 8)
        .frame(width: Self.width, height: 40)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(Theme.leafLine, lineWidth: 1))
        .shadow(color: Theme.shadowStrong, radius: 10, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inline-add-bar")
        .onAppear { typing.wrappedValue = true }
        .onChange(of: bar.parent) { _, _ in typing.wrappedValue = true }
    }

    private func icon(_ name: String, label: String, help: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .foregroundStyle(Theme.text3)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}
#endif
