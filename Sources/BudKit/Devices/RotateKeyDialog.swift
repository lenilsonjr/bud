#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// Rotating the key (G8): shown after Remove and rotate, or from Rotate the key. Each device
/// reports as it takes the new key; one that is apart cannot answer, so after a short wait the
/// dialog closes on the result and the notice above the list takes over.
struct RotateKeyDialog: View {
    @ObservedObject var devices: DeviceStore
    let close: () -> Void

    /// How long the result stays on screen before the dialog closes itself.
    static let linger: Duration = .seconds(1.2)

    var body: some View {
        RotateKeyBody(
            lines: DevicesText.rotationLines(
                devices.devices, progress: devices.rotation, kind: DevicesText.platform(isPad: DevicesSection.isPad)),
            count: DevicesText.rotationCount(devices.rotation)
        )
        .task(id: devices.rotation?.result) {
            guard devices.rotation?.result != nil else { return }
            try? await Task.sleep(for: Self.linger)
            guard !Task.isCancelled else { return }
            devices.dismissRotation()
            close()
        }
    }
}

/// The dialog's face, drawn from its lines so a picture needs no node.
struct RotateKeyBody: View {
    let lines: [DevicesText.RotationLine]
    let count: String

    private static var titleStyle: TextStyle { TextStyle(typeface: .display, size: 24, weight: 500) }
    private static var bodyStyle: TextStyle { TextStyle(typeface: .text, size: 13, weight: 400) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rotating the key")
                .textStyle(Self.titleStyle)
                .foregroundStyle(Theme.text)
            Text("Sending a new key to the devices that remain, over the connection they already have.")
                .textStyle(Self.bodyStyle)
                .lineSpacing(13 * 0.5)
                .foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
            list
            HStack {
                Spacer()
                Text(count)
                    .textRole(.label)
                    .monospacedDigit()
                    .foregroundStyle(Theme.text3)
            }
        }
        .textRole(.body)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var list: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        return VStack(spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                if index > 0 { Theme.line.frame(height: 1) }
                row(line)
            }
        }
        .background(Theme.raised, in: shape)
        .overlay(shape.stroke(Theme.line, lineWidth: 1))
    }

    private func row(_ line: DevicesText.RotationLine) -> some View {
        HStack(spacing: 10) {
            mark(line.state)
                .frame(width: 16, height: 16)
            Text(PeerText.shortID(line.id))
                .textRole(.mono)
                .foregroundStyle(Theme.text)
            Spacer(minLength: 8)
            Text(line.label)
                .textRole(.caption)
                .foregroundStyle(ink(line.state))
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
    }

    @ViewBuilder private func mark(_ state: DevicesText.RotationLine.State) -> some View {
        switch state {
        case .newKey:
            Image(systemName: "key.fill").resizable().scaledToFit().foregroundStyle(Theme.leaf)
        case .gotIt:
            Image(systemName: "checkmark.circle.fill").resizable().scaledToFit().foregroundStyle(Theme.leaf)
        case .waiting:
            Circle().stroke(Theme.text3, lineWidth: 1.5).padding(3)
        case .missed:
            Image(systemName: "xmark.circle").resizable().scaledToFit().foregroundStyle(Theme.rose)
        }
    }

    private func ink(_ state: DevicesText.RotationLine.State) -> Color {
        switch state {
        case .newKey, .gotIt: return Theme.text2
        case .waiting: return Theme.text3
        case .missed: return Theme.rose
        }
    }
}
#endif
