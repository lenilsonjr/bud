import Foundation

/// The words of Add a device nearby (G19 on the phone), kept pure so they test on their own.
public enum NearbyText {
    public static let title = "Add a device nearby"
    public static let scanHint = "Point the camera at the code on the other device, under Add this Apple TV to a vault."
    public static let looking = "Looking for a code"
    public static let wordsTitle = "Do these words match?"
    public static let wordsNote = "They should read the same on the other device. Add sends this vault’s key to it."
    public static let waiting = "Press Select on the other device to let it in."
    public static let addedTitle = "Added"

    /// "Ada’s Apple TV is in the vault and fetching it now.", or the kind alone.
    public static func addedBody(_ device: Device) -> String {
        let who = device.displayName ?? "The \(DevicesText.deviceWord(device.kind))"
        return "\(who) is in the vault and fetching it now."
    }

    public static func failureTitle(_ error: RequestError) -> String {
        switch error {
        case .notARequest: return "That isn’t a Bud code"
        case .expired: return "That code ran out"
        case .unreachable: return "Couldn’t reach the other device"
        case .refused: return "The other device said no"
        }
    }

    public static func failureBody(_ error: RequestError) -> String {
        switch error {
        case .notARequest: return "Scan the code the other device shows under Add this Apple TV to a vault."
        case .expired: return "Each code works for ten minutes. The other device shows a new one; scan that."
        case .unreachable: return "Keep it on its code, on the same network or online, and try again."
        case .refused: return "It refused the key, or it is in another vault already. Scan its code again to retry."
        }
    }
}

#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// Add a device nearby: the camera opens at once looking for the code another device shows; a code
/// read puts its six words up with Add; Add waits for the person at the other device to press
/// Select, then says it is in. A failure names what happened and scans again.
struct NearbySheet: View {
    @ObservedObject var devices: DeviceStore
    let close: () -> Void

    @State private var scanning = false
    @State private var cameraDenied = false

    /// A launch argument for a tour over memory, where the simulator has no camera: the sheet
    /// reads a code the memory peers make, as if it had scanned one. Debug builds only.
    static let tourArgument = "-bud-nearby"
    static var touring: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains(tourArgument)
        #else
        return false
        #endif
    }

    var body: some View {
        NearbySheetBody(
            phase: devices.requestPhase,
            scanning: scanning,
            cameraDenied: cameraDenied,
            onAdd: { Task { await devices.confirmRequest() } },
            onScanAgain: { devices.resetRequest(); scanning = true },
            onClose: { devices.resetRequest(); close() },
            scanner: { AnyView(scanner) })
        // The key cannot be called back once Add is pressed: the sheet stays until the other
        // device answers.
        .interactiveDismissDisabled(devices.requestPhase == .confirming)
        .task {
            devices.resetRequest()
            await openCamera()
        }
        .onDisappear { devices.resetRequest() }
    }

    private func openCamera() async {
        if Self.touring && !DevicesSection.canScan {
            await devices.openRequest()
            let code = devices.currentRequest?.code
            devices.closeRequest()
            if let code { await devices.readRequest(code) }
            return
        }
        #if os(iOS)
        guard TicketScanner.isAvailable else { return }
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
            // A request, or anything else that starts like a Bud code and is named as not one.
            guard code.lowercased().hasPrefix("bud") else { return }
            scanning = false
            Task { await devices.readRequest(code) }
        }
        #else
        EmptyView()
        #endif
    }
}

/// The sheet itself, drawn from values so a picture can show any of its states.
struct NearbySheetBody: View {
    let phase: RequestPhase
    var scanning = false
    var cameraDenied = false
    let onAdd: () -> Void
    let onScanAgain: () -> Void
    let onClose: () -> Void
    var scanner: () -> AnyView = { AnyView(EmptyView()) }

    @Environment(\.compact) private var compact

    private static let barTitle = TextStyle(typeface: .text, size: 17, weight: 600)
    private static let title = TextStyle(typeface: .display, size: 28, weight: 500)
    private static let note = TextStyle(typeface: .text, size: 15, weight: 400)
    private static let word = TextStyle(typeface: .text, size: 17, weight: 600)
    private static let failureTitle = TextStyle(typeface: .text, size: 15, weight: 600)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            head
            switch phase {
            case .idle:
                if scanning {
                    scan
                } else {
                    if cameraDenied { denied }
                    wide(title: "Scan a code", systemImage: "viewfinder", action: onScanAgain, style: .budPrimary)
                        .disabled(cameraDenied)
                        .opacity(cameraDenied ? 0.4 : 1)
                }
            case .reading:
                waitingRow("Reading the code…")
            case let .words(words, _):
                wordsState(words, waiting: false)
            case .confirming:
                waitingRow(NearbyText.waiting)
            case let .confirmed(device):
                added(device)
            case let .failed(error):
                failure(error)
                wide(title: "Scan again", systemImage: "viewfinder", action: onScanAgain, style: .budPrimary)
            }
        }
        .textRole(.body)
        .tint(Theme.leaf)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var done: Bool {
        if case .confirmed = phase { return true }
        return false
    }

    private var head: some View {
        ZStack {
            if !done && phase != .confirming {
                HStack {
                    Button("Cancel", action: onClose)
                        .buttonStyle(.plain)
                        .font(Theme.font(TextStyle(typeface: .text, size: 17, weight: 400)))
                        .foregroundStyle(Theme.leaf)
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                }
            }
            Text(NearbyText.title)
                .textStyle(Self.barTitle)
                .foregroundStyle(Theme.text)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.bottom, 4)
    }

    // MARK: Scanning

    private var scan: some View {
        VStack(alignment: .leading, spacing: 16) {
            let shape = RoundedRectangle(cornerRadius: Radius.detail, style: .continuous)
            scanner()
                .frame(maxWidth: .infinity)
                .frame(height: compact ? 400 : 300)
                .background(Theme.hubInk.opacity(0.08))
                .clipShape(shape)
                .overlay(alignment: .bottom) {
                    HStack(spacing: 6) {
                        Image(systemName: "viewfinder")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.leaf)
                        Text(NearbyText.looking)
                            .textRole(.cardTitle)
                            .foregroundStyle(Theme.text)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Theme.glass, in: Capsule())
                    .padding(.bottom, 14)
                }
            Text(NearbyText.scanHint)
                .textStyle(Self.note)
                .foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var denied: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "video.slash")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.kraftInk)
                .frame(width: 16, height: 18)
            Text(JoinText.cameraDenied)
                .textRole(.cardTitle)
                .fontWeight(.regular)
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.kraft, in: RoundedRectangle(cornerRadius: Radius.toast, style: .continuous))
    }

    // MARK: Words

    private func wordsState(_ words: [String], waiting: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(NearbyText.wordsTitle)
                .textStyle(Self.title)
                .foregroundStyle(Theme.text)
            wordGrid(words)
            Text(NearbyText.wordsNote)
                .textStyle(Self.note)
                .foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
            wide(title: "Add", systemImage: "plus", action: onAdd, style: .budPrimary)
            wide(title: "They don’t match", action: onClose, style: .budGhost)
        }
    }

    /// The six words in two rows of three, the same order as on the other device.
    private func wordGrid(_ words: [String]) -> some View {
        VStack(spacing: 8) {
            ForEach(Array(stride(from: 0, to: words.count, by: 3)), id: \.self) { start in
                HStack(spacing: 8) {
                    ForEach(Array(words[start..<min(start + 3, words.count)].enumerated()), id: \.offset) { _, word in
                        Text(word)
                            .textStyle(Self.word)
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Theme.leafSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(words.joined(separator: ", "))
    }

    private func waitingRow(_ text: String) -> some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(text)
                .textStyle(Self.note)
                .foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }

    // MARK: Outcomes

    private func added(_ device: Device) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack {
                Circle().fill(Theme.leafSoft)
                Image(systemName: "checkmark")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Theme.leaf)
            }
            .frame(width: 64, height: 64)
            .padding(.top, 24)
            .accessibilityHidden(true)
            Text(NearbyText.addedTitle)
                .textStyle(Self.title)
                .foregroundStyle(Theme.text)
            Text(NearbyText.addedBody(device))
                .textStyle(Self.note)
                .foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
            wide(title: "Done", action: onClose, style: .budPrimary)
                .padding(.top, 8)
        }
    }

    private func failure(_ error: RequestError) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.rose)
                .frame(width: 16, height: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(NearbyText.failureTitle(error))
                    .textStyle(Self.failureTitle)
                    .foregroundStyle(Theme.text)
                Text(NearbyText.failureBody(error))
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
#endif
