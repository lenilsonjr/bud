import Foundation

/// The words of the join sheet, kept pure so they test on their own.
public enum JoinText {
    /// The three failures of the frame, word for word.
    public static func failureTitle(_ error: AcceptError) -> String {
        switch error {
        case .usedOrExpired: return "That ticket was already used"
        case .notATicket: return "That isn’t a Bud ticket"
        case .unreachable: return "Couldn’t reach the other device"
        }
    }

    public static func failureBody(_ error: AcceptError) -> String {
        switch error {
        case .usedOrExpired: return "Each ticket works once, for ten minutes. Ask the other device for a fresh one."
        case .notATicket: return "It should start with bud1. Check for a missing piece."
        case .unreachable: return "Keep it open, on the same network or online, and try again."
        }
    }

    /// The line under the camera and the notice when it cannot be used.
    public static let scanHint = "Point the camera at the ticket on the device that has the vault."
    public static let cameraDenied = "Bud can’t use the camera. Type or paste the ticket, or turn the camera on."
    public static let typeHint = "Paste the ticket from a device that has the vault. Spaces and capitals don’t matter."

    /// "on the local network", "through a relay", "directly".
    public static func reachPhrase(_ reach: Reach) -> String {
        switch reach {
        case .local: return "on the local network"
        case .relay: return "through a relay"
        case .direct: return "directly"
        }
    }

    /// "Getting buds from a91c…7t0e on the local network. You can start while it finishes."
    public static func joinedBody(from device: Device) -> String {
        "Getting buds from \(PeerText.shortID(device.id)) \(reachPhrase(device.reach)). You can start while it finishes."
    }

    /// "214 of 1,380 buds", or "214 buds so far" while the total is not known.
    public static func progress(received: Int, total: Int?) -> String {
        guard let total else { return received == 1 ? "1 bud so far" : "\(grouped(received)) buds so far" }
        return "\(grouped(received)) of \(grouped(total)) buds"
    }

    /// How far the first sync is, 0...1, or nil while the total is not known.
    public static func fraction(received: Int, total: Int?) -> Double? {
        guard let total, total > 0 else { return nil }
        return min(1, Double(received) / Double(total))
    }

    /// 1380 as "1,380".
    static func grouped(_ number: Int) -> String {
        let digits = Array(String(number))
        var out = ""
        for (index, digit) in digits.enumerated() {
            if index > 0 && (digits.count - index) % 3 == 0 { out.append(",") }
            out.append(digit)
        }
        return out
    }
}

/// What the entry field's footer says.
public enum EntryStatus: Equatable, Sendable {
    /// "37 of 134" while the text is short of a ticket.
    case typing(count: String)
    /// The text has the shape of a ticket; Join wakes.
    case looksLikeTicket
    /// The text was sent and turned away; it stays so it can be fixed.
    case checked

    public init(text: String, failed: Bool) {
        if failed {
            self = .checked
        } else if PeerText.looksLikeTicket(text) {
            self = .looksLikeTicket
        } else {
            self = .typing(count: PeerText.typedCount(text))
        }
    }

    public var label: String {
        switch self {
        case let .typing(count): return count
        case .looksLikeTicket: return "Looks like a ticket"
        case .checked: return "Checked"
        }
    }

    public var canJoin: Bool { self == .looksLikeTicket }
}

#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// Add this device to a vault: on iPhone and iPad the camera opens at once looking for a Bud
/// code, with typing one tap away; on the Mac, and when the camera is denied, the text field with
/// Paste ready. A readable ticket goes straight to checking; a failure keeps the text and names
/// what happened; joined shows the first sync in place.
struct JoinSheet: View {
    @ObservedObject var devices: DeviceStore
    let close: () -> Void

    @State private var text = ""
    @State private var scanning = false
    @State private var cameraDenied = false

    var body: some View {
        JoinSheetBody(
            phase: devices.joinPhase,
            text: $text,
            scanning: scanning,
            canScan: Self.canScan,
            cameraDenied: cameraDenied,
            onPaste: paste,
            onJoin: { Task { await devices.join(text: text) } },
            onTypeInstead: { scanning = false },
            onScanAgain: { devices.resetJoin(); text = ""; scanning = true },
            onEdit: { devices.resetJoin() },
            onClose: { devices.resetJoin(); close() },
            scanner: { AnyView(scanner) })
        .onChange(of: text) { _, new in
            let grouped = PeerText.grouped(new).lowercased()
            if grouped != new { text = grouped }
            if case .failed = devices.joinPhase { devices.resetJoin() }
        }
        .task { await openCamera() }
    }

    /// Whether this build can scan at all: the Mac path never does.
    static var canScan: Bool {
        #if os(iOS)
        return TicketScanner.isAvailable
        #else
        return false
        #endif
    }

    /// Asks for the camera once; denied means the typed path with the notice.
    private func openCamera() async {
        #if os(iOS)
        guard Self.canScan else { return }
        if await TicketScanner.authorize() {
            scanning = true
        } else {
            cameraDenied = true
        }
        #endif
    }

    @ViewBuilder private var scanner: some View {
        #if os(iOS)
        TicketScanner { code in
            guard PeerText.looksLikeTicket(code) else { return }
            text = PeerText.grouped(code).lowercased()
            scanning = false
            Task { await devices.join(text: code) }
        }
        #else
        EmptyView()
        #endif
    }

    private func paste() {
        #if os(macOS)
        let pasted = NSPasteboard.general.string(forType: .string)
        #else
        let pasted = UIPasteboard.general.string
        #endif
        guard let pasted else { return }
        text = PeerText.grouped(pasted).lowercased()
    }
}

/// The sheet itself, drawn from values so a picture can show any of its states. Compact widths
/// take the phone layout: Cancel and the title in a bar, full-width buttons; the rest take the
/// Mac card with its actions in a row.
struct JoinSheetBody: View {
    let phase: JoinPhase
    @Binding var text: String
    var scanning = false
    var canScan = false
    var cameraDenied = false
    let onPaste: () -> Void
    let onJoin: () -> Void
    let onTypeInstead: () -> Void
    let onScanAgain: () -> Void
    let onEdit: () -> Void
    let onClose: () -> Void
    var scanner: () -> AnyView = { AnyView(EmptyView()) }

    @Environment(\.compact) private var compact

    private static let title = TextStyle(typeface: .text, size: 16, weight: 600)
    private static let barTitle = TextStyle(typeface: .text, size: 17, weight: 600)
    private static let joinedTitle = TextStyle(typeface: .display, size: 28, weight: 500)
    private static let note = TextStyle(typeface: .text, size: 12, weight: 400)
    private static let phoneNote = TextStyle(typeface: .text, size: 15, weight: 400)
    private static let failureTitle = TextStyle(typeface: .text, size: 15, weight: 600)

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 16 : 18) {
            head
            switch phase {
            case let .joined(device, received, total):
                joined(device, received: received, total: total)
            case let .failed(error):
                entry(status: .checked)
                failure(error)
                failedActions
            case .checking:
                entry(status: .typing(count: "Checking…"))
                joinActions(enabled: false)
            case .idle:
                if scanning && canScan {
                    scan
                } else {
                    if cameraDenied && text.isEmpty { denied }
                    entry(status: EntryStatus(text: text, failed: false))
                    joinActions(enabled: EntryStatus(text: text, failed: false).canJoin)
                }
            }
        }
        .textRole(.body)
        .tint(Theme.leaf)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Head

    @ViewBuilder private var head: some View {
        if compact {
            ZStack {
                if !isJoined {
                    HStack {
                        Button("Cancel", action: onClose)
                            .buttonStyle(.plain)
                            .font(Theme.font(TextStyle(typeface: .text, size: 17, weight: 400)))
                            .foregroundStyle(Theme.leaf)
                            .keyboardShortcut(Keys.shortcut(.close))
                        Spacer()
                    }
                }
                Text("Join a vault")
                    .textStyle(Self.barTitle)
                    .foregroundStyle(Theme.text)
            }
            .padding(.bottom, 4)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Join a vault")
                    .textStyle(Self.title)
                    .foregroundStyle(Theme.text)
                if !isJoined && !(scanning && canScan) {
                    Text(JoinText.typeHint)
                        .textStyle(Self.note)
                        .foregroundStyle(Theme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var isJoined: Bool {
        if case .joined = phase { return true }
        return false
    }

    // MARK: Scanning

    private var scan: some View {
        VStack(alignment: .leading, spacing: 16) {
            viewfinder
            Text(JoinText.scanHint)
                .textStyle(Self.phoneNote)
                .foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
            wide(title: "Type or paste instead", action: onTypeInstead, style: .budGhost)
        }
    }

    private var viewfinder: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.detail, style: .continuous)
        return scanner()
            .frame(maxWidth: .infinity)
            .frame(height: compact ? 400 : 300)
            .background(Theme.hubInk.opacity(0.08))
            .clipShape(shape)
            .overlay { corners }
            .overlay(alignment: .bottom) {
                HStack(spacing: 6) {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.leaf)
                    Text("Looking for a ticket")
                        .textRole(.cardTitle)
                        .foregroundStyle(Theme.text)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Theme.glass, in: Capsule())
                .padding(.bottom, 14)
            }
    }

    /// The four corner marks of the viewfinder.
    private var corners: some View {
        GeometryReader { box in
            let size: CGFloat = 48
            let path = Path { path in
                let w = box.size.width
                let h = box.size.height
                path.move(to: CGPoint(x: 0, y: size)); path.addLine(to: CGPoint(x: 0, y: 0)); path.addLine(to: CGPoint(x: size, y: 0))
                path.move(to: CGPoint(x: w - size, y: 0)); path.addLine(to: CGPoint(x: w, y: 0)); path.addLine(to: CGPoint(x: w, y: size))
                path.move(to: CGPoint(x: w, y: h - size)); path.addLine(to: CGPoint(x: w, y: h)); path.addLine(to: CGPoint(x: w - size, y: h))
                path.move(to: CGPoint(x: size, y: h)); path.addLine(to: CGPoint(x: 0, y: h)); path.addLine(to: CGPoint(x: 0, y: h - size))
            }
            path.stroke(Theme.raised.opacity(0.9), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
        .padding(14)
    }

    // MARK: Typing

    private var denied: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "video.slash")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.kraftInk)
                .frame(width: 16, height: 18)
            VStack(alignment: .leading, spacing: 4) {
                Text(JoinText.cameraDenied)
                    .textRole(.cardTitle)
                    .fontWeight(.regular)
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Settings", action: openSettings)
                    .buttonStyle(.plain)
                    .textRole(.cardTitle)
                    .foregroundStyle(Theme.kraftInk)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.kraft, in: RoundedRectangle(cornerRadius: Radius.toast, style: .continuous))
    }

    private func openSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        #endif
    }

    private func entry(status: EntryStatus) -> some View {
        TicketEntryField(text: $text, status: status, onPaste: compact ? onPaste : nil)
    }

    @ViewBuilder private func joinActions(enabled: Bool) -> some View {
        if compact {
            wide(title: "Join", systemImage: "arrow.right.to.line", action: onJoin, style: .budPrimary)
                .disabled(!enabled)
                .opacity(enabled ? 1 : 0.4)
        } else {
            HStack(spacing: 8) {
                Button(action: onPaste) { BudButtonLabel(title: "Paste", systemImage: "doc.on.clipboard") }
                    .buttonStyle(.budGhost)
                Spacer()
                #if os(macOS)
                Keycap(Keys.key(for: .close))
                #endif
                Button(action: onClose) { BudButtonLabel(title: "Cancel") }
                    .buttonStyle(.budSecondary)
                    .keyboardShortcut(Keys.shortcut(.close))
                Button(action: onJoin) { BudButtonLabel(title: "Join", systemImage: "arrow.right.to.line") }
                    .buttonStyle(.budPrimary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!enabled)
                    .opacity(enabled ? 1 : 0.4)
            }
            .padding(.top, 4)
        }
    }

    // MARK: Failed

    private func failure(_ error: AcceptError) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.rose)
                .frame(width: 16, height: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(JoinText.failureTitle(error))
                    .textStyle(Self.failureTitle)
                    .foregroundStyle(Theme.text)
                Text(JoinText.failureBody(error))
                    .textRole(.cardTitle)
                    .fontWeight(.regular)
                    .foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.roseSoft, in: RoundedRectangle(cornerRadius: Radius.toast, style: .continuous))
    }

    @ViewBuilder private var failedActions: some View {
        if compact {
            VStack(spacing: 8) {
                if canScan {
                    wide(title: "Scan a new ticket", systemImage: "viewfinder", action: onScanAgain, style: .budPrimary)
                }
                wide(title: "Edit the text", action: onEdit, style: .budGhost)
            }
        } else {
            HStack(spacing: 8) {
                Button(action: onPaste) { BudButtonLabel(title: "Paste", systemImage: "doc.on.clipboard") }
                    .buttonStyle(.budGhost)
                Spacer()
                #if os(macOS)
                Keycap(Keys.key(for: .close))
                #endif
                Button(action: onClose) { BudButtonLabel(title: "Cancel") }
                    .buttonStyle(.budSecondary)
                    .keyboardShortcut(Keys.shortcut(.close))
                Button(action: onEdit) { BudButtonLabel(title: "Edit the text") }
                    .buttonStyle(.budPrimary)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
    }

    // MARK: Joined

    private func joined(_ device: Device, received: Int, total: Int?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack {
                Circle().fill(Theme.leafSoft)
                Image(systemName: "checkmark")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Theme.leaf)
            }
            .frame(width: 64, height: 64)
            .padding(.top, compact ? 24 : 4)
            Text("Joined the vault")
                .textStyle(Self.joinedTitle)
                .foregroundStyle(Theme.text)
            Text(JoinText.joinedBody(from: device))
                .textStyle(compact ? Self.phoneNote : TextRole.body.style)
                .foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 8) {
                SyncBar(fraction: JoinText.fraction(received: received, total: total))
                HStack {
                    Text(JoinText.progress(received: received, total: total))
                    Spacer()
                    Text(DevicesText.reachWord(device.reach))
                }
                .textRole(.cardTitle)
                .fontWeight(.regular)
                .foregroundStyle(Theme.text3)
                .monospacedDigit()
            }
            .padding(.vertical, 10)
            if compact {
                wide(title: "Done", action: onClose, style: .budPrimary)
                    .padding(.top, 8)
            } else {
                HStack(spacing: 8) {
                    #if os(macOS)
                    Keycap(Keys.key(for: .close))
                    #endif
                    Spacer()
                    Button(action: onClose) { BudButtonLabel(title: "Done") }
                        .buttonStyle(.budPrimary)
                        .keyboardShortcut(Keys.shortcut(.close))
                }
            }
        }
    }

    /// A full-width 46 pt button for the phone layout.
    private func wide(title: String, systemImage: String? = nil, action: @escaping () -> Void, style: BudButtonStyle) -> some View {
        Button(action: action) {
            BudButtonLabel(title: title, systemImage: systemImage)
                .font(Theme.font(TextStyle(typeface: .text, size: 15, weight: 600)))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
        }
        .buttonStyle(style)
    }
}

/// The first sync's bar: 6 pt, leaf on leafSoft, or a sliding third while the total is unknown.
struct SyncBar: View {
    let fraction: Double?
    @Environment(\.stillPicture) private var still
    @State private var slide = false

    var body: some View {
        GeometryReader { box in
            let width = box.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.leafSoft)
                if let fraction {
                    Capsule().fill(Theme.leaf).frame(width: max(6, width * fraction))
                } else {
                    Capsule().fill(Theme.leaf)
                        .frame(width: width / 3)
                        .offset(x: slide && !still ? width * 2 / 3 : 0)
                        .animation(still ? nil : .easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: slide)
                        .onAppear { slide = true }
                }
            }
        }
        .frame(height: 6)
    }
}
#endif
