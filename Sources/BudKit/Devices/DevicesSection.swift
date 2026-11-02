#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// The DEVICES section of Settings: the notice for a missed key, the list or the invitation, the
/// two ways in and the Relay control. It reads from `DeviceStore` and opens the sheets and dialogs
/// through `present`.
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
            if let notice {
                Text(notice)
                    .textRole(.caption)
                    .foregroundStyle(Theme.rose)
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

    private var invitation: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Only this \(DevicesText.deviceWord(kind)) so far. Pair another device to keep your buds in step.")
                .textRole(.body)
                .foregroundStyle(Theme.text2)
            ways
        }
    }

    /// The two ways in: side by side on the Mac, stacked and full width on iPhone and iPad.
    @ViewBuilder private var ways: some View {
        if stacked {
            VStack(spacing: 8) {
                ticketButton.frame(maxWidth: .infinity)
                joinButton.frame(maxWidth: .infinity)
            }
        } else {
            HStack(spacing: 8) {
                ticketButton
                joinButton
            }
        }
    }

    private var ticketButton: some View {
        Button { present(.showTicket) } label: { BudButtonLabel(title: "Show a ticket", systemImage: "qrcode").frame(maxWidth: stacked ? .infinity : nil) }
            .buttonStyle(.budSecondary)
    }

    private var joinButton: some View {
        Button { present(.joinVault) } label: {
            BudButtonLabel(title: "Add this \(DevicesText.deviceWord(kind)) to a vault").frame(maxWidth: stacked ? .infinity : nil)
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
            Text("A relay carries sealed traffic between devices that are not on the same network.")
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

/// The sheet or dialog a device modal stands for. `go` moves to another modal or, with nil, closes;
/// `back` is where a closed one returns to (Settings, when Settings is itself a modal).
struct DeviceModalView: View {
    let modal: Modal
    @ObservedObject var devices: DeviceStore
    let go: (Modal?) -> Void
    let back: Modal?

    var body: some View {
        switch modal {
        case .showTicket: TicketSheet(devices: devices, close: { go(back) })
        case .joinVault: JoinSheet(devices: devices, close: { go(back) })
        case .removeDevice(let id):
            RemoveDeviceDialog(devices: devices, id: id, close: { go(back) }, rotate: { go(.rotateKey) })
        case .rotateKey: RotateKeyDialog(devices: devices, close: { go(back) })
        default: EmptyView()
        }
    }
}
#endif
