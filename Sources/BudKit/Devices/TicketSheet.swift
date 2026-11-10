import Foundation

/// What the ticket sheet shows, from the ticket on hand, the clock and whether a device took it.
public enum TicketSheetState: Hashable, Sendable {
    /// No ticket yet: the node is making one.
    case making
    /// A ticket that still works, with the time left as "9:58".
    case fresh(countdown: String)
    /// Ten minutes passed or the ticket was used; Refresh makes a new one.
    case expired
    /// A device took the ticket; its short id leads the sheet.
    case joined(shortID: String)

    public init(ticket: Ticket?, now: Date, redeemedBy: String?) {
        if let redeemedBy {
            self = .joined(shortID: PeerText.shortID(redeemedBy))
        } else if let ticket {
            self = ticket.expiresAt <= now ? .expired : .fresh(countdown: PeerText.countdown(until: ticket.expiresAt, now: now))
        } else {
            self = .making
        }
    }

    /// The footer line of the code field.
    public var status: String {
        switch self {
        case let .fresh(countdown): return "Works once · expires in \(countdown)"
        case .expired: return "Expired · works once, for ten minutes"
        case .making, .joined: return ""
        }
    }

    public var isExpired: Bool { self == .expired }
}

#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// Show a ticket: the code to scan and the text to send, counting down; a device that takes it
/// turns the sheet into "joined". The store makes the ticket while the sheet is open and lets it
/// go when the sheet closes.
struct TicketSheet: View {
    @ObservedObject var devices: DeviceStore
    let close: () -> Void
    @State private var copied = false
    @State private var copyReset: Task<Void, Never>?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            TicketSheetBody(
                ticket: devices.currentTicket,
                state: TicketSheetState(ticket: devices.currentTicket, now: context.date, redeemedBy: devices.redeemedBy),
                copied: copied,
                onCopy: copy,
                onRefresh: { Task { await devices.refreshTicketIfExpired() } },
                onDone: close)
        }
        .task { await devices.openTicket() }
        .onDisappear { devices.closeTicket() }
    }

    private func copy() {
        guard let text = devices.currentTicket?.text else { return }
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
        copied = true
        copyReset?.cancel()
        copyReset = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if !Task.isCancelled { copied = false }
        }
    }
}

/// The sheet itself, drawn from values so a picture can show any of its states.
struct TicketSheetBody: View {
    let ticket: Ticket?
    let state: TicketSheetState
    var copied = false
    let onCopy: () -> Void
    let onRefresh: () -> Void
    let onDone: () -> Void

    private static let title = TextStyle(typeface: .display, size: 24, weight: 500)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if case let .joined(shortID) = state {
                Text("\(shortID) joined")
                    .textStyle(Self.title)
                    .foregroundStyle(Theme.text)
                Text("It's getting the vault now. You can close this; the first sync carries on.")
                    .textRole(.body)
                    .foregroundStyle(Theme.text2)
            } else {
                Text("Show a ticket")
                    .textStyle(Self.title)
                    .foregroundStyle(Theme.text)
                Text("On the new device, open Settings › Devices › Add this device to a vault. Then scan this, or paste the text.")
                    .textRole(.body)
                    .foregroundStyle(Theme.text2)
                if let ticket {
                    QRTile(modules: ticket.qr, expired: state.isExpired)
                        .frame(maxWidth: .infinity)
                    TicketCodeField(
                        text: ticket.text, status: state.status, expired: state.isExpired, copied: copied,
                        onCopy: onCopy, onRefresh: onRefresh)
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .frame(height: 216)
                }
                if !state.isExpired {
                    Text("Waiting for the new device…")
                        .textRole(.caption)
                        .foregroundStyle(Theme.text3)
                }
            }
            HStack(spacing: 8) {
                #if os(macOS)
                Keycap(Keys.key(for: .close))
                #endif
                Spacer()
                Button(action: onDone) { BudButtonLabel(title: "Done") }
                    .buttonStyle(.budPrimary)
                    .keyboardShortcut(Keys.shortcut(.close))
            }
        }
        .textRole(.body)
        .tint(Theme.leaf)
    }
}
#endif
