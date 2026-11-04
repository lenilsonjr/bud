import Foundation

/// What the window is showing over everything else. One at a time; nil is nothing.
enum Modal: Hashable, Identifiable {
    case add(parent: UUID)
    case capture
    case closeBranch(id: UUID)
    case settings
    /// Delete one branch from the Trash for good; with nil, empty the whole Trash.
    case deleteForever(id: UUID?)
    /// Settings › Devices: the ticket sheet, the join sheet, and the two dialogs.
    case showTicket
    case joinVault
    /// Scan the code a device without the vault shows, and send it the key.
    case addNearby
    case removeDevice(id: String)
    case rotateKey
    /// Settings › Start over: erase this device's vault, empty or with the sample world.
    case freshStart

    static let settingsID = UUID(uuidString: "00000000-0000-0000-0000-00000000000F")!
    static let emptyTrashID = UUID(uuidString: "00000000-0000-0000-0000-00000000000E")!
    static let showTicketID = UUID(uuidString: "00000000-0000-0000-0000-0000000000D1")!
    static let joinVaultID = UUID(uuidString: "00000000-0000-0000-0000-0000000000D2")!
    static let addNearbyID = UUID(uuidString: "00000000-0000-0000-0000-0000000000D5")!
    static let removeDeviceID = UUID(uuidString: "00000000-0000-0000-0000-0000000000D3")!
    static let rotateKeyID = UUID(uuidString: "00000000-0000-0000-0000-0000000000D4")!
    static let freshStartID = UUID(uuidString: "00000000-0000-0000-0000-0000000000F1")!

    var id: UUID {
        switch self {
        case .add(let parent): return parent
        case .capture: return inboxID
        case .closeBranch(let id): return id
        case .settings: return Self.settingsID
        case .deleteForever(let id): return id ?? Self.emptyTrashID
        case .showTicket: return Self.showTicketID
        case .joinVault: return Self.joinVaultID
        case .addNearby: return Self.addNearbyID
        case .removeDevice: return Self.removeDeviceID
        case .rotateKey: return Self.rotateKeyID
        case .freshStart: return Self.freshStartID
        }
    }

    /// An add on the canvas plants where it was asked, the hub included: only the capture button
    /// and the ⌥Space panel send a line to the Inbox.
    static func adding(under id: UUID) -> Modal {
        .add(parent: id)
    }
}

/// The measures of the card a modal sits on.
enum ModalMetrics {
    static let padding: CGFloat = 24
    static let width: CGFloat = 480
    static let margin: CGFloat = 16
    static let appearScale: CGFloat = 0.96
    static let appearDuration: Double = 0.18

    /// 480 pt, or the window width minus 32 when the window is narrower than that.
    static func cardWidth(window: CGFloat) -> CGFloat {
        min(width, window - 2 * margin)
    }
}

#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// The overlay the root view owns: a scrim over the whole window and the card in the middle, or
/// at the bottom edge above the safe area on a compact width. A click on the scrim closes it.
struct ModalHost: View {
    @ObservedObject var store: BudStore
    @Environment(\.compact) private var compact

    var body: some View {
        ZStack {
            if let modal = store.modal {
                scrim
                GeometryReader { window in
                    card(for: modal)
                        .frame(width: ModalMetrics.cardWidth(window: window.size.width))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: compact ? .bottom : .center)
                        .padding(.bottom, compact ? ModalMetrics.margin : 0)
                }
                .id(modal)
                .transition(.scale(scale: ModalMetrics.appearScale).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: ModalMetrics.appearDuration), value: store.modal)
    }

    private var scrim: some View {
        Theme.scrim
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture {
                // A key on its way cannot be called back: the card stays until the other device
                // answers.
                if store.modal == .addNearby && store.devices.requestPhase == .confirming { return }
                store.modal = nil
            }
            .transition(.opacity)
    }

    @ViewBuilder private func card(for modal: Modal) -> some View {
        Group {
            switch modal {
            case .add(let parent): AddSheet(store: store, mode: .enrich(under: parent))
            case .capture: AddSheet(store: store, mode: .capture)
            case .closeBranch(let id): CloseBranchDialog(store: store, id: id)
            case .settings:
                SettingsView(flags: .shared, devices: store.devices, onDone: { store.modal = nil }, present: { store.modal = $0 })
            case .deleteForever(let id): DeleteForeverDialog(store: store, id: id)
            case .showTicket: TicketSheet(devices: store.devices, close: { store.modal = .settings })
            case .joinVault: JoinSheet(devices: store.devices, close: { store.modal = .settings })
            case .addNearby: NearbySheet(devices: store.devices, close: { store.modal = .settings })
            case let .removeDevice(id):
                RemoveDeviceDialog(
                    devices: store.devices, id: id, close: { store.modal = .settings }, present: { store.modal = $0 })
            case .rotateKey: RotateKeyDialog(devices: store.devices, close: { store.modal = .settings })
            case .freshStart:
                FreshStartDialog(close: { store.modal = .settings }, perform: { store.freshStart(sample: $0) })
            }
        }
        .modalCard()
    }
}

extension View {
    /// The raised card: fill, 1 pt stroke, 22 pt corners and 24 pt of padding.
    func modalCard() -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous)
        return padding(ModalMetrics.padding)
            .background(Theme.raised, in: shape)
            .overlay(shape.stroke(Theme.lineStrong, lineWidth: 1))
    }
}
#endif
