#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// One device of the list, as the Device row specimen draws it: the reach icon, the short id, the
/// seen label and a Remove action. A device that missed the new key says so and offers Pair again
/// in place of Remove; this device has no action. A long press or a right click opens the same
/// action as a menu, the way a bud's row does.
struct DeviceRow: View {
    let device: Device
    let now: Date
    let onRemove: () -> Void
    let onPairAgain: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: Self.symbol(for: device.reach))
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .foregroundStyle(device.missed ? Theme.rose : Theme.text3)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if device.isThisDevice {
                        Text(DevicesText.thisDevice(DevicesText.platform(isPad: DevicesSection.isPad)))
                            .textRole(.cardTitle)
                            .foregroundStyle(Theme.text)
                    }
                    Text(PeerText.shortID(device.id))
                        .textRole(.mono)
                        .foregroundStyle(device.isThisDevice ? Theme.text3 : Theme.text)
                }
                Text(caption)
                    .textRole(.caption)
                    .foregroundStyle(device.missed ? Theme.rose : Theme.text3)
            }
            Spacer(minLength: 8)
            action
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        .contextMenu {
            if device.missed {
                Button("Pair again", systemImage: "qrcode", action: onPairAgain)
            }
            if !device.isThisDevice {
                Button("Remove", systemImage: "trash", role: .destructive, action: onRemove)
            }
        }
    }

    private var caption: String {
        DevicesText.rowCaption(device, kind: DevicesText.platform(isPad: DevicesSection.isPad), now: now)
    }

    @ViewBuilder private var action: some View {
        if device.isThisDevice {
            EmptyView()
        } else if device.missed {
            Button(action: onPairAgain) { BudButtonLabel(title: "Pair again") }
                .buttonStyle(.budGhost)
        } else {
            Button(action: onRemove) { BudButtonLabel(title: "Remove") }
                .buttonStyle(.budSecondary)
        }
    }

    /// The reach icon: local network, relay, direct.
    static func symbol(for reach: Reach) -> String {
        switch reach {
        case .local: return "wifi"
        case .relay: return "arrow.triangle.swap"
        case .direct: return "link"
        }
    }
}
#endif
