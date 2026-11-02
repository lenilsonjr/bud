#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// Remove this device (G7): forget it, and by default make a new key so it cannot read what comes
/// next. Esc cancels, Return removes.
struct RemoveDeviceDialog: View {
    @ObservedObject var devices: DeviceStore
    let id: String
    let close: () -> Void
    /// Moves on to the Rotating the key dialog.
    let rotate: () -> Void
    @State private var rotateKey = true

    private static let title = TextStyle(typeface: .display, size: 24, weight: 500)
    private static let body = TextStyle(typeface: .text, size: 13, weight: 400)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Remove this device")
                .textStyle(Self.title)
                .foregroundStyle(Theme.text)
            Text("\(PeerText.shortID(id)) stops syncing with this vault. It still holds the key it has, so a new key keeps it from reading what you write next.")
                .textStyle(Self.body)
                .lineSpacing(13 * 0.5)
                .foregroundStyle(Theme.text2)
            VStack(spacing: 8) {
                RadioChoice(on: rotateKey, title: "Remove and rotate the key", caption: "Gives every other device a new key. Recommended.") { rotateKey = true }
                RadioChoice(on: !rotateKey, title: "Remove only", caption: "The device could still read what you write next.") { rotateKey = false }
            }
            HStack(spacing: 8) {
                Spacer()
                Button(action: close) { BudButtonLabel(title: "Cancel") }
                    .buttonStyle(.budSecondary)
                    .keyboardShortcut(.cancelAction)
                Button(action: remove) { BudButtonLabel(title: "Remove") }
                    .buttonStyle(.budDestructive)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .textRole(.body)
        .tint(Theme.leaf)
    }

    private func remove() {
        let withRotation = rotateKey
        let target = id
        let devices = devices
        Task { await devices.remove(target, rotate: withRotation) }
        if withRotation { rotate() } else { close() }
    }
}

/// A radio row drawn in SwiftUI: the ring at the left, a title and a caption.
struct RadioChoice: View {
    let on: Bool
    let title: String
    let caption: String
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
        Button(action: action) {
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
