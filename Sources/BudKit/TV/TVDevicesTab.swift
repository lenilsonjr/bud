#if canImport(SwiftUI) && os(tvOS)
import SwiftUI

/// One device as the TV draws it: a 112 pt raised row with the reach mark in a lit square, the
/// short id with the This Apple TV tag, and the reach and seen label. It is a button so the
/// remote can land on it; the focus look is drawn here, not lifted.
struct TVDeviceRow: View {
    let device: Device
    let now: Date
    let lit: Bool

    private static let id = TextStyle(typeface: .mono, size: 30, weight: 400)
    private static let name = TextStyle(typeface: .text, size: 30, weight: 500)
    private static let tag = TextStyle(typeface: .text, size: 20, weight: 600)
    private static let meta = TextStyle(typeface: .text, size: 22, weight: 400)

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        Button {} label: {
            HStack(spacing: 26) {
                Image(systemName: symbol)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(Theme.leaf)
                    .frame(width: 60, height: 60)
                    .background(Theme.lit, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 14) {
                        Text(device.displayName ?? PeerText.shortID(device.id))
                            .textStyle(device.displayName == nil ? Self.id : Self.name)
                            .foregroundStyle(Theme.text)
                        if device.isThisDevice {
                            Text("This Apple TV")
                                .textStyle(Self.tag)
                                .foregroundStyle(Theme.text2)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(Theme.lit, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                    Text(caption)
                        .textStyle(Self.meta)
                        .foregroundStyle(device.missed ? Theme.rose : Theme.text3)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 30)
            .frame(maxWidth: .infinity)
            .frame(height: 112)
            .background(lit ? Theme.amethystSoft : Theme.raised, in: shape)
            .overlay(shape.stroke(lit ? Theme.amethyst : Theme.line, lineWidth: lit ? 2 : 1))
            .shadow(color: lit ? Theme.amethyst.opacity(0.35) : .clear, radius: lit ? 24 : 0)
        }
        .buttonStyle(.tvBare)
        .animation(.easeOut(duration: 0.2), value: lit)
    }

    private var caption: String {
        if device.isThisDevice { return TVDevicesText.thisDevice }
        return DevicesText.rowCaption(device, kind: .tv, now: now)
    }

    private var symbol: String {
        if device.isThisDevice { return "tv" }
        switch device.kind {
        case .mac: return "laptopcomputer"
        case .iphone: return "iphone"
        case .ipad: return "ipad"
        case .tv: return "tv"
        case nil:
            switch device.reach {
            case .local: return "wifi"
            case .relay: return "antenna.radiowaves.left.and.right"
            case .direct: return "link"
            }
        }
    }
}

/// PAIR THE NEXT DEVICE: the 280 pt QR tile with the ticket on show, the instruction, the expiry
/// that counts down, and the button that joins a vault from here instead.
struct TVPairColumn: View {
    @ObservedObject var devices: DeviceStore
    let lit: Bool
    let onJoin: () -> Void

    private static let eyebrow = TextStyle(typeface: .text, size: 20, weight: 700, tracking: 1.6, uppercase: true)
    private static let note = TextStyle(typeface: .text, size: 24, weight: 400)
    private static let expiry = TextStyle(typeface: .text, size: 20, weight: 400)
    private static let button = TextStyle(typeface: .text, size: 29, weight: 600)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 28) {
                Text("Pair the next device")
                    .textStyle(Self.eyebrow)
                    .foregroundStyle(Theme.leaf)
                if let ticket = devices.currentTicket {
                    QRTile(modules: ticket.qr, size: 280, corner: 24, expired: context.date >= ticket.expiresAt)
                } else {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Theme.hubInk)
                        .frame(width: 280, height: 280)
                        .overlay { ProgressView().tint(Theme.hub) }
                }
                Text(TVDevicesText.pairNote)
                    .textStyle(Self.note)
                    .foregroundStyle(Theme.text2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(TVDevicesText.expiry(devices.currentTicket, now: context.date))
                    .textStyle(Self.expiry)
                    .foregroundStyle(Theme.text3)
                    .monospacedDigit()
                Spacer(minLength: 0)
                joinButton
            }
        }
        .padding(44)
        .frame(width: 620)
        .frame(maxHeight: .infinity)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .task {
            await devices.openTicket()
        }
        .onDisappear { devices.closeTicket() }
    }

    private var joinButton: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return Button(action: onJoin) {
            HStack(spacing: 14) {
                Image(systemName: "arrow.right.to.line")
                    .font(.system(size: 26, weight: .semibold))
                Text("Add this Apple TV to a vault")
                    .textStyle(Self.button)
            }
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 40)
            .frame(width: 532, height: 84)
            .background(lit ? Theme.amethystSoft : Theme.raised, in: shape)
            .overlay(shape.stroke(lit ? Theme.amethyst : Theme.line, lineWidth: lit ? 2 : 1))
            .shadow(color: lit ? Theme.amethyst.opacity(0.35) : .clear, radius: lit ? 24 : 0)
        }
        .buttonStyle(.tvBare)
        .animation(.easeOut(duration: 0.2), value: lit)
    }
}
#endif
