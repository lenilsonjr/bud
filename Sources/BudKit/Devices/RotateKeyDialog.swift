#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// Rotating the key (G8): one line per device with its state as the core reports it, the count,
/// and the result at the end. When the core only reports the result afterwards there is a single
/// progress line.
struct RotateKeyDialog: View {
    @ObservedObject var devices: DeviceStore
    let close: () -> Void
    @State private var started = false

    private static let title = TextStyle(typeface: .display, size: 24, weight: 500)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rotating the key")
                .textStyle(Self.title)
                .foregroundStyle(Theme.text)
            if let progress = devices.rotation {
                content(progress)
            } else {
                Text("Making the new key")
                    .textRole(.body)
                    .foregroundStyle(Theme.text2)
            }
        }
        .textRole(.body)
        .tint(Theme.leaf)
        .onChange(of: devices.rotation != nil) { _, now in
            if now { started = true } else if started { close() }
        }
    }

    @ViewBuilder private func content(_ progress: RotationProgress) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(DevicesText.rotationLines(progress, devices: devices.devices)) { line in
                Text(line.text)
                    .textRole(.body)
                    .foregroundStyle(Theme.text2)
            }
        }
        if let result = progress.result {
            Text(DevicesText.result(result))
                .textRole(.body)
                .foregroundStyle(result.missed.isEmpty ? Theme.text : Theme.rose)
            HStack {
                Spacer()
                Button(action: done) { BudButtonLabel(title: "Done") }
                    .buttonStyle(.budPrimary)
                    .keyboardShortcut(.defaultAction)
            }
        } else {
            Text(DevicesText.count(progress))
                .textRole(.caption)
                .foregroundStyle(Theme.text3)
        }
    }

    private func done() {
        devices.dismissRotation()
        close()
    }
}
#endif
