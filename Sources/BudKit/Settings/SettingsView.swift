#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// Settings: Appearance, the vault folder, Devices and Start over. A Try section returns whenever two layouts need
/// comparing on a device before one is kept. On the Mac it is the Settings window (⌘,); on iPhone and
/// iPad it is a modal from the gear in the top bar, with Done to close it.
public struct SettingsView: View {
    @ObservedObject private var flags: Flags
    @ObservedObject private var devices: DeviceStore
    private let onDone: (() -> Void)?
    /// Opens a sheet or dialog over the window; nil in the Mac Settings window, which has no modal
    /// of its own and shows them as sheets.
    private let present: ((Modal) -> Void)?
    @State private var local: Modal?

    private static let title = TextStyle(typeface: .display, size: 24, weight: 500)

    @MainActor public init() {
        self.init(flags: .shared, devices: .shared, onDone: nil, present: nil)
    }

    init(flags: Flags, devices: DeviceStore, onDone: (() -> Void)?, present: ((Modal) -> Void)?) {
        self.flags = flags
        self.devices = devices
        self.onDone = onDone
        self.present = present
    }

    public var body: some View {
        Group {
            if let onDone {
                // A modal on iPhone and iPad: the title and Done stay put and the sections scroll
                // between them once they are taller than the card the window allows.
                VStack(alignment: .leading, spacing: 20) {
                    heading
                    ViewThatFits(in: .vertical) {
                        sections
                        MaybeScroll { sections.frame(maxWidth: .infinity, alignment: .leading) }
                    }
                    HStack {
                        Spacer()
                        Button(action: onDone) { BudButtonLabel(title: "Done") }
                            .buttonStyle(.budPrimary)
                            .keyboardShortcut(.defaultAction)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    heading
                    sections
                }
                .frame(minWidth: 360, alignment: .leading)
                .padding(24)
            }
        }
        .textRole(.body)
        .foregroundStyle(Theme.text)
        .tint(Theme.leaf)
        .sheet(item: $local) { modal in
            Group {
                switch modal {
                case .showTicket: TicketSheet(devices: devices, close: { local = nil })
                case .joinVault: JoinSheet(devices: devices, close: { local = nil })
                case .addNearby: NearbySheet(devices: devices, close: { local = nil })
                case let .removeDevice(id):
                    RemoveDeviceDialog(devices: devices, id: id, close: { local = nil }, present: { local = $0 })
                case .rotateKey: RotateKeyDialog(devices: devices, close: { local = nil })
                case .freshStart:
                    // The Mac's Settings window has no store; the root view performs the request on its own.
                    FreshStartDialog(close: { local = nil }, perform: { sample in
                        NotificationCenter.default.post(name: BudStore.freshStartRequested, object: nil, userInfo: ["sample": sample])
                        local = nil
                    })
                case let .connectMail(account):
                    ConnectMailSheet(sources: .shared, account: account, close: { local = nil })
                case .connectCalendar: ConnectCalendarSheet(sources: .shared, close: { local = nil })
                case let .calendars(account): ConnectCalendarSheet(sources: .shared, account: account, close: { local = nil })
                case .connectLinear: ConnectTokenSheet(sources: .shared, kind: .linear, close: { local = nil })
                case .connectGitHub: ConnectTokenSheet(sources: .shared, kind: .github, close: { local = nil })
                default: EmptyView()
                }
            }
            .frame(width: ModalMetrics.width - 2 * ModalMetrics.padding)
            .padding(ModalMetrics.padding)
            .background(Theme.raised)
        }
    }

    private var heading: some View {
        Text("Settings")
            .textStyle(Self.title)
            .foregroundStyle(Theme.text)
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: 20) {
            section("Appearance", caption: "Bud follows the system until you pick a side.") {
                Segmented(selection: $flags.appearance, options: Appearance.allCases) { $0.rawValue }
            }
            section("Vault", caption: "The folder of Markdown files Bud reads and writes.") {
                Text(vaultPath)
                    .textRole(.mono)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .foregroundStyle(Theme.text3)
                    .textSelection(.enabled)
            }
            DevicesSection(devices: devices, present: { modal in
                if let present { present(modal) } else { local = modal }
            })
            SourcesSection(sources: .shared, present: { modal in
                if let present { present(modal) } else { local = modal }
            })
            section("Start over", caption: "Erases every bud on this device and starts again, empty or with the sample vault.") {
                Button {
                    if let present { present(.freshStart) } else { local = .freshStart }
                } label: {
                    BudButtonLabel(title: "Start over…", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.budDestructive)
            }
        }
    }

    private var vaultPath: String {
        BudStore.defaultFile?.deletingLastPathComponent().path ?? "Not saved on this device"
    }

    private func section(_ name: String, caption: String, @ViewBuilder control: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(name.uppercased())
                .textRole(.eyebrow)
                .foregroundStyle(Theme.text3)
            control()
            Text(caption)
                .textRole(.caption)
                .foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#endif
