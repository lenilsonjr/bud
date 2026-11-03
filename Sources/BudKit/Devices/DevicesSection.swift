#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// The DEVICES section of Settings: the intro line, the notice for a missed key, the list or the
/// invitation, the two ways in with Rotate the key beside them, and the Relay control. It reads
/// from `DeviceStore` and opens the sheets and dialogs through `present`.
struct DevicesSection: View {
    @ObservedObject var devices: DeviceStore
    let present: (Modal) -> Void

    @State private var showCustom = false
    @State private var customText = ""

    /// Whether this build runs on an iPad.
    static var isPad: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad
        #else
        return false
        #endif
    }

    private var kind: DeviceKind { DevicesText.platform(isPad: Self.isPad) }
    private var stacked: Bool {
        #if os(iOS)
        return true
        #else
        return false
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DEVICES")
                .textRole(.eyebrow)
                .foregroundStyle(Theme.text3)
            Text(DevicesText.intro)
                .textRole(.caption)
                .foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
            if let notice {
                Text(notice)
                    .textRole(.caption)
                    .foregroundStyle(Theme.rose)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if DevicesText.isEmpty(devices.devices) {
                invitation
            } else {
                list
                ways
            }
            relay
        }
        .task { await devices.refresh() }
    }

    private var notice: String? {
        DevicesText.notice(missed: devices.devices.filter(\.missed).count, since: devices.rotatedAt)
    }

    // MARK: List and invitation

    private var list: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
        let rows = DevicesText.ordered(devices.devices)
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, device in
                if index > 0 { Theme.line.frame(height: 1) }
                DeviceRow(
                    device: device, now: Date(), onRemove: { present(.removeDevice(id: device.id)) },
                    onPairAgain: { present(.showTicket) })
            }
        }
        .background(Theme.raised, in: shape)
        .overlay(shape.stroke(Theme.line, lineWidth: 1))
    }

    private static let invitationBody = TextStyle(typeface: .text, size: 12, weight: 400)

    private var invitation: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(DevicesText.alone(kind))
                    .textRole(.cardTitle)
                    .foregroundStyle(Theme.text)
                Text(DevicesText.invitation(kind))
                    .textStyle(Self.invitationBody)
                    .lineSpacing(12 * 0.45)
                    .foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
            ways
        }
    }

    /// The two ways in, and Rotate the key once there is another device: in one row on the Mac,
    /// with Rotate the key on a row of its own when the three do not fit; stacked and full width
    /// on iPhone and iPad.
    @ViewBuilder private var ways: some View {
        let others = !DevicesText.isEmpty(devices.devices)
        if stacked {
            VStack(spacing: 8) {
                if Self.canScan || NearbySheet.touring { nearbyButton.frame(maxWidth: .infinity) }
                ticketButton.frame(maxWidth: .infinity)
                joinButton.frame(maxWidth: .infinity)
                if others { rotateButton.frame(maxWidth: .infinity) }
            }
        } else if others {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    ticketButton
                    joinButton
                    Spacer(minLength: 0)
                    rotateButton
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        ticketButton
                        joinButton
                    }
                    rotateButton
                }
            }
        } else {
            HStack(spacing: 8) {
                ticketButton
                joinButton
            }
        }
    }

    private var rotateButton: some View {
        Button {
            present(.rotateKey)
            Task { await devices.rotateKey() }
        } label: {
            BudButtonLabel(title: "Rotate the key", systemImage: "key", iconAfter: true)
                .lineLimit(1)
                .frame(maxWidth: stacked ? .infinity : nil)
        }
        .buttonStyle(.budGhost)
    }

    /// Whether this device can scan another's code: iPhone and iPad with a camera.
    static var canScan: Bool {
        #if os(iOS)
        return TicketScanner.isAvailable
        #else
        return false
        #endif
    }

    /// Add a device nearby (G19): scan the code an Apple TV or another device without the vault shows.
    private var nearbyButton: some View {
        Button { present(.addNearby) } label: {
            BudButtonLabel(title: NearbyText.title, systemImage: "viewfinder").lineLimit(1).frame(maxWidth: .infinity)
        }
        .buttonStyle(.budPrimary)
    }

    private var ticketButton: some View {
        Button { present(.showTicket) } label: {
            BudButtonLabel(title: "Show a ticket", systemImage: "qrcode").lineLimit(1).frame(maxWidth: stacked ? .infinity : nil)
        }
            .buttonStyle(.budSecondary)
    }

    private var joinButton: some View {
        Button { present(.joinVault) } label: {
            BudButtonLabel(title: "Add this \(DevicesText.deviceWord(kind)) to a vault").lineLimit(1).frame(maxWidth: stacked ? .infinity : nil)
        }
        .buttonStyle(.budSecondary)
    }

    // MARK: Relay

    private var relay: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Relay")
                .textRole(.label)
                .foregroundStyle(Theme.text2)
                .padding(.top, 8)
            Segmented(selection: choice, options: RelayChoice.allCases) { $0.title }
            if choice.wrappedValue == .custom {
                TextField("https://relay.example.com", text: $customText)
                    .textFieldStyle(.plain)
                    .textRole(.mono)
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Theme.sidebar, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Theme.line, lineWidth: 1))
                    .onSubmit { commitCustom() }
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                    .autocorrectionDisabled()
            }
            Text(DevicesText.relayCaption)
                .textRole(.caption)
                .foregroundStyle(Theme.text3)
        }
        .onAppear { if case let .custom(url) = devices.relay { customText = url.absoluteString } }
    }

    private var choice: Binding<RelayChoice> {
        Binding(
            get: { showCustom ? .custom : RelayChoice(devices.relay) },
            set: { picked in
                showCustom = picked == .custom
                switch picked {
                case .publicRelays: Task { await devices.setRelay(.default) }
                case .off: Task { await devices.setRelay(.off) }
                case .custom: commitCustom()
                }
            })
    }

    private func commitCustom() {
        guard let url = RelayChoice.url(from: customText) else { return }
        Task { await devices.setRelay(.custom(url)) }
    }
}
#endif
