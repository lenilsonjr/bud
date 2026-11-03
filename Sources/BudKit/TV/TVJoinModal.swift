#if canImport(SwiftUI) && os(tvOS)
import SwiftUI

/// Join a vault on Apple TV (G17): a proper full-screen modal. The ticket is typed on the one-line
/// tvOS keyboard, grouped in fives with the count; the line under it points at the iPhone
/// keyboard, which is the comfortable way. Join wakes when the text looks like a ticket, Menu
/// cancels. A failure keeps the text and names what happened.
struct TVJoinModal: View {
    @ObservedObject var devices: DeviceStore
    let close: () -> Void
    @State private var text = ""
    @FocusState private var focus: Field?

    enum Field: Hashable { case ticket, join, cancel }

    private static let title = TextStyle(typeface: .display, size: 64, weight: 500)
    private static let note = TextStyle(typeface: .text, size: 26, weight: 400)
    private static let code = TextStyle(typeface: .mono, size: 36, weight: 400)
    private static let count = TextStyle(typeface: .text, size: 22, weight: 400)
    private static let aside = TextStyle(typeface: .text, size: 24, weight: 400)
    private static let failureTitle = TextStyle(typeface: .text, size: 28, weight: 600)
    private static let button = TextStyle(typeface: .text, size: 29, weight: 600)

    private var status: EntryStatus {
        if case .failed = devices.joinPhase { return .checked }
        return EntryStatus(text: text, failed: false)
    }

    private var canJoin: Bool {
        if case .checking = devices.joinPhase { return false }
        return status.canJoin
    }

    var body: some View {
        VStack(spacing: 40) {
            Text("Join a vault")
                .textStyle(Self.title)
                .foregroundStyle(Theme.text)
            Text(TVDevicesText.joinNote)
                .textStyle(Self.note)
                .foregroundStyle(Theme.text2)
            field
            if case let .failed(error) = devices.joinPhase { failure(error) }
            HStack(spacing: 14) {
                Image(systemName: "iphone")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Theme.leaf)
                Text(TVDevicesText.phoneKeyboard)
                    .textStyle(Self.aside)
                    .foregroundStyle(Theme.text2)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Spacer(minLength: 0)
            HStack(spacing: 24) {
                kitButton("Join", systemImage: "arrow.right.to.line", primary: true, lit: focus == .join, enabled: canJoin) {
                    Task { await devices.join(text: text) }
                }
                .focused($focus, equals: .join)
                kitButton("Cancel", primary: false, lit: focus == .cancel, enabled: true, action: cancel)
                    .focused($focus, equals: .cancel)
            }
        }
        .padding(.top, 110)
        .padding(.horizontal, 200)
        .padding(.bottom, 80)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.window.ignoresSafeArea())
        .textRole(.body)
        .foregroundStyle(Theme.text)
        .onExitCommand(perform: cancel)
        .onChange(of: text) { _, new in
            let grouped = PeerText.grouped(new).lowercased()
            if grouped != new { text = grouped }
            if case .failed = devices.joinPhase { devices.resetJoin() }
        }
        .onAppear { focus = .ticket }
    }

    private var field: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        return VStack(alignment: .leading, spacing: 14) {
            TextField("bud1 …", text: $text)
                .textFieldStyle(.plain)
                .font(Theme.font(Self.code))
                .foregroundStyle(Theme.text)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($focus, equals: .ticket)
                .onSubmit { if canJoin { Task { await devices.join(text: text) } } }
            HStack(spacing: 10) {
                Image(systemName: status == .looksLikeTicket ? "checkmark.circle" : "keyboard")
                    .font(.system(size: 20, weight: .medium))
                Text(status.label)
                    .textStyle(Self.count)
                    .monospacedDigit()
            }
            .foregroundStyle(status == .looksLikeTicket ? Theme.leaf : Theme.text3)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 26)
        .frame(width: 1240)
        .background(Theme.raised, in: shape)
        .overlay(shape.stroke(focus == .ticket ? Theme.amethyst : Theme.lineStrong, lineWidth: focus == .ticket ? 2 : 1))
    }

    private func failure(_ error: AcceptError) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Theme.rose)
            VStack(alignment: .leading, spacing: 4) {
                Text(JoinText.failureTitle(error))
                    .textStyle(Self.failureTitle)
                    .foregroundStyle(Theme.text)
                Text(JoinText.failureBody(error))
                    .textStyle(Self.aside)
                    .foregroundStyle(Theme.text2)
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 18)
        .frame(width: 1240, alignment: .leading)
        .background(Theme.roseSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func kitButton(
        _ title: String, systemImage: String? = nil, primary: Bool, lit: Bool, enabled: Bool, action: @escaping () -> Void
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return Button(action: action) {
            HStack(spacing: 14) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 26, weight: .semibold))
                }
                Text(title).textStyle(Self.button)
            }
            .foregroundStyle(primary ? Theme.onLeaf : Theme.text)
            .frame(width: 300, height: 84)
            .background(primary ? Theme.leafFill : (lit ? Theme.amethystSoft : Theme.raised), in: shape)
            .overlay(shape.stroke(lit ? Theme.amethyst : (primary ? .clear : Theme.line), lineWidth: lit ? 2 : 1))
            .shadow(color: lit ? Theme.amethyst.opacity(0.35) : .clear, radius: lit ? 24 : 0)
            .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(.tvBare)
        .disabled(!enabled)
        .animation(.easeOut(duration: 0.2), value: lit)
    }

    private func cancel() {
        devices.resetJoin()
        close()
    }
}

/// First sync on Apple TV (G18): the TV keeps its copy in a cache and starts empty, so after
/// joining it fetches everything before it shows a card. One quiet screen; the caller takes it
/// away when the fetch is over.
struct TVFetchScreen: View {
    let device: Device
    let received: Int
    let total: Int?

    private static let title = TextStyle(typeface: .display, size: 72, weight: 500)
    private static let body = TextStyle(typeface: .text, size: 28, weight: 400)
    private static let meta = TextStyle(typeface: .text, size: 24, weight: 400)

    var body: some View {
        VStack(spacing: 34) {
            ZStack {
                Circle().fill(Theme.leafSoft)
                Image(systemName: "leaf")
                    .font(.system(size: 52, weight: .medium))
                    .foregroundStyle(Theme.leaf)
            }
            .frame(width: 120, height: 120)
            Text("Getting your buds")
                .textStyle(Self.title)
                .foregroundStyle(Theme.text)
            Text(TVDevicesText.fetchBody(from: device))
                .textStyle(Self.body)
                .foregroundStyle(Theme.text2)
                .multilineTextAlignment(.center)
            VStack(spacing: 16) {
                GeometryReader { box in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.lineStrong)
                        Capsule().fill(Theme.leaf)
                            .frame(width: max(10, box.size.width * (JoinText.fraction(received: received, total: total) ?? 0.08)))
                    }
                }
                .frame(height: 10)
                HStack {
                    Text(JoinText.progress(received: received, total: total))
                    Spacer()
                    Text(TVDevicesText.fetchNote)
                }
                .textStyle(Self.meta)
                .foregroundStyle(Theme.text3)
                .monospacedDigit()
            }
            .padding(.top, 20)
        }
        .padding(.horizontal, 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.window.ignoresSafeArea())
    }
}
#endif
