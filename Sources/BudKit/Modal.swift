import Foundation

/// What the window is showing over everything else. One at a time; nil is nothing.
enum Modal: Hashable, Identifiable {
    case add(parent: UUID)
    case capture
    case closeBranch(id: UUID)
    case settings
    /// Delete one branch from the Trash for good; with nil, empty the whole Trash.
    case deleteForever(id: UUID?)

    static let settingsID = UUID(uuidString: "00000000-0000-0000-0000-00000000000F")!
    static let emptyTrashID = UUID(uuidString: "00000000-0000-0000-0000-00000000000E")!

    var id: UUID {
        switch self {
        case .add(let parent): return parent
        case .capture: return inboxID
        case .closeBranch(let id): return id
        case .settings: return Self.settingsID
        case .deleteForever(let id): return id ?? Self.emptyTrashID
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
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var compact: Bool { sizeClass == .compact }
    #else
    private var compact: Bool { false }
    #endif

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
            case .settings: SettingsView(flags: .shared, onDone: { store.modal = nil })
            case .deleteForever(let id): DeleteForeverDialog(store: store, id: id)
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
