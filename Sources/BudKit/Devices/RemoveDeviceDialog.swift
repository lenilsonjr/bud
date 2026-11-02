#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// Remove this device (G7): the kit dialog with two choices. Rotating is the default, since a
/// removal alone only turns the device away and the key it holds still opens anything it already
/// has. Esc cancels, Return removes.
struct RemoveDeviceDialog: View {
    @ObservedObject var devices: DeviceStore
    let id: String
    let close: () -> Void
    let present: (Modal) -> Void
    @State private var rotate = true

    var body: some View {
        DialogBody(
            title: "Remove \(PeerText.shortID(id))?",
            text: "It stops syncing from now on, even if it still holds the key. What is already on it stays there."
        ) {
            VStack(spacing: 8) {
                DialogChoice(
                    on: rotate, title: "Remove and rotate the key",
                    caption: "The other devices switch to a new key over the connection they have now.") { rotate = true }
                DialogChoice(on: !rotate, title: "Remove only", caption: "Rotate the key later from Devices.") { rotate = false }
            }
        } actions: {
            Button(action: close) { BudButtonLabel(title: "Cancel") }
                .buttonStyle(.budSecondary)
                .keyboardShortcut(.cancelAction)
            Button(action: remove) { BudButtonLabel(title: "Remove this device") }
                .buttonStyle(.budDestructive)
                .keyboardShortcut(.defaultAction)
        }
    }

    /// The rotation dialog takes over at once and closes on the result; it also closes when the
    /// node refuses the removal, since no rotation starts then.
    private func remove() {
        let rotate = rotate
        if rotate { present(.rotateKey) } else { close() }
        Task {
            let removed = await devices.remove(id, rotate: rotate)
            if rotate && !removed { close() }
        }
    }
}

/// The kit dialog: a 24 pt display title, a 13 pt body, the choices and the actions on the right.
struct DialogBody<Choices: View, Actions: View>: View {
    let title: String
    let text: String
    @ViewBuilder let choices: () -> Choices
    @ViewBuilder let actions: () -> Actions

    private static var titleStyle: TextStyle { TextStyle(typeface: .display, size: 24, weight: 500) }
    private static var bodyStyle: TextStyle { TextStyle(typeface: .text, size: 13, weight: 400) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .textStyle(Self.titleStyle)
                .foregroundStyle(Theme.text)
            Text(text)
                .textStyle(Self.bodyStyle)
                .lineSpacing(13 * 0.5)
                .foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
            choices()
            HStack(spacing: 8) {
                Spacer()
                actions()
            }
            .padding(.top, 6)
        }
        .textRole(.body)
        .tint(Theme.leaf)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One of a dialog's choices: a radio, a title and a note, lit when chosen.
struct DialogChoice: View {
    let on: Bool
    let title: String
    let caption: String
    let pick: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        Button(action: pick) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle().stroke(on ? Theme.leaf : Theme.text3, lineWidth: 1.5)
                    if on { Circle().fill(Theme.leaf).padding(4) }
                }
                .frame(width: 16, height: 16)
                .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .textRole(.cardTitle)
                        .foregroundStyle(Theme.text)
                    Text(caption)
                        .textRole(.caption)
                        .foregroundStyle(Theme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(on ? Theme.leafSoft : .clear, in: shape)
            .overlay(shape.stroke(on ? Theme.leafLine : Theme.line, lineWidth: on ? 1.5 : 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
    }
}
#endif
