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
    case removeDevice(id: String)
    case rotateKey

    static let settingsID = UUID(uuidString: "00000000-0000-0000-0000-00000000000F")!
    static let emptyTrashID = UUID(uuidString: "00000000-0000-0000-0000-00000000000E")!
    static let showTicketID = UUID(uuidString: "00000000-0000-0000-0000-0000000000D1")!
    static let joinVaultID = UUID(uuidString: "00000000-0000-0000-0000-0000000000D2")!
    static let rotateKeyID = UUID(uuidString: "00000000-0000-0000-0000-0000000000D3")!

    /// A stable identity for a device id, which is text and not a UUID.
    private static func identity(of text: String) -> UUID {
        var first: UInt64 = 0xcbf2_9ce4_8422_2325
        var second: UInt64 = 0x8422_2325_cbf2_9ce4
        for byte in text.utf8 {
            first = (first ^ UInt64(byte)) &* 0x100_0000_01b3
            second = (second &+ UInt64(byte)) &* 0x9E37_79B9_7F4A_7C15
        }
        var bytes = (0..<8).map { UInt8(truncatingIfNeeded: first >> UInt64($0 * 8)) }
        bytes += (0..<8).map { UInt8(truncatingIfNeeded: second >> UInt64($0 * 8)) }
        bytes[0] = 0xD4
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    var id: UUID {
        switch self {
        case .add(let parent): return parent
        case .capture: return inboxID
        case .closeBranch(let id): return id
        case .settings: return Self.settingsID
        case .deleteForever(let id): return id ?? Self.emptyTrashID
        case .showTicket: return Self.showTicketID
        case .joinVault: return Self.joinVaultID
        case .removeDevice(let id): return Self.identity(of: id)
        case .rotateKey: return Self.rotateKeyID
        }
    }

    /// Enrich under an ordinary card; the hub is not a place to plant under, so it captures into
    /// the Inbox instead.
    static func adding(under id: UUID) -> Modal {
        switch PlantTarget.forCenter(id) {
        case .inbox: return .capture
        case .under(let parent): return .add(parent: parent)
        }
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
            .onTapGesture { store.modal = nil }
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
            case .showTicket, .joinVault, .removeDevice, .rotateKey:
                DeviceModalView(modal: modal, devices: store.devices, go: { store.modal = $0 }, back: .settings)
            }
        }
        .modalCard()
    }
}

extension View {
    /// The raised card: fill, 1 pt stroke, 22 pt corners and 24 pt of padding.
    func modalCard() -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
        return padding(ModalMetrics.padding)
            .background(Theme.raised, in: shape)
            .overlay(shape.stroke(Theme.lineStrong, lineWidth: 1))
    }
}
#endif
