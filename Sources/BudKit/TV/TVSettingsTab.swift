#if canImport(SwiftUI) && os(tvOS)
import SwiftUI

/// Settings on Apple TV, grown out of Devices as G16 allows: Appearance and Start over at the
/// top of the left column, then the devices with this Apple TV first and the press and hold
/// line; the column that pairs the next device on the right. Focus is the soft amethyst glow
/// with no lift.
struct TVSettingsTab: View {
    @ObservedObject var store: BudStore
    @ObservedObject var devices: DeviceStore
    @ObservedObject var flags: Flags
    let onJoin: () -> Void
    /// The vault was erased: the shell shows the canvas, where the change is in view.
    let onStartOver: () -> Void
    @State private var startingOver = false
    @FocusState private var focused: String?

    private static let title = TextStyle(typeface: .display, size: 64, weight: 500)
    private static let eyebrow = TextStyle(typeface: .text, size: 20, weight: 700, tracking: 1.6, uppercase: true)
    private static let status = TextStyle(typeface: .text, size: 24, weight: 400)
    private static let caption = TextStyle(typeface: .text, size: 22, weight: 400)
    private static let hint = TextStyle(typeface: .text, size: 22, weight: 400)
    private static let choice = TextStyle(typeface: .text, size: 26, weight: 500)

    var body: some View {
        HStack(alignment: .top, spacing: 120) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Settings")
                        .textStyle(Self.title)
                        .foregroundStyle(Theme.text)
                        .padding(.bottom, 10)
                    eyebrow("Appearance")
                    appearance
                    Text(TVSettingsText.appearanceCaption)
                        .textStyle(Self.caption)
                        .foregroundStyle(Theme.text3)
                    eyebrow("Start over").padding(.top, 20)
                    TVKitButton(title: "Start over…", systemImage: "arrow.counterclockwise", kind: .destructive, lit: focused == "start-over") {
                        startingOver = true
                    }
                    .focused($focused, equals: "start-over")
                    Text(TVSettingsText.startOverCaption)
                        .textStyle(Self.caption)
                        .foregroundStyle(Theme.text3)
                    eyebrow("Devices").padding(.top, 20)
                    HStack(spacing: 12) {
                        Circle().fill(connected ? Theme.leaf : Theme.text3).frame(width: 12, height: 12)
                        Text(TVDevicesText.status(devices.syncState))
                            .textStyle(Self.status)
                            .foregroundStyle(Theme.text2)
                    }
                    ForEach(DevicesText.ordered(devices.devices)) { device in
                        TVDeviceRow(device: device, now: Date(), lit: focused == device.id)
                            .focused($focused, equals: device.id)
                            .contextMenu {
                                if !device.isThisDevice {
                                    Button("Remove", systemImage: "trash", role: .destructive) {
                                        Task { await devices.remove(device.id, rotate: false) }
                                    }
                                    Button("Remove and rotate the key", systemImage: "key") {
                                        Task { await devices.remove(device.id, rotate: true) }
                                    }
                                }
                                Button("Rotate the key", systemImage: "key") {
                                    Task { await devices.rotateKey() }
                                }
                            }
                    }
                    Text(TVDevicesText.holdHint)
                        .textStyle(Self.hint)
                        .foregroundStyle(Theme.text3)
                        .padding(.top, 8)
                }
                .padding(.vertical, 30)
            }
            .scrollClipDisabled()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .focusSection()
            // A TV with no other device asks to be let in (G19); one with a vault pairs the next.
            if DevicesText.isEmpty(devices.devices) {
                TVRequestColumn(devices: devices, lit: focused == "join", onType: onJoin)
                    .focused($focused, equals: "join")
                    .focusSection()
            } else {
                TVPairColumn(devices: devices, lit: focused == "join", onJoin: onJoin)
                    .focused($focused, equals: "join")
                    .focusSection()
            }
        }
        .padding(.top, 30)
        .padding(.horizontal, 160)
        .padding(.bottom, 90)
        .task { await devices.refresh() }
        // A key on offer takes focus, so Select answers it at once.
        .onChange(of: devices.offer) { _, offer in
            if offer != nil { focused = "join" }
        }
        .fullScreenCover(isPresented: $startingOver) {
            TVFreshStartScreen(close: { startingOver = false }, perform: { sample in
                store.freshStart(sample: sample)
                startingOver = false
                onStartOver()
            })
        }
    }

    private func eyebrow(_ text: String) -> some View {
        Text(text)
            .textStyle(Self.eyebrow)
            .foregroundStyle(Theme.leaf)
    }

    /// System, Light, Dark as three buttons in one raised pill; the chosen one reads in full ink.
    private var appearance: some View {
        HStack(spacing: 8) {
            ForEach(Appearance.allCases, id: \.self) { item in
                let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
                let lit = focused == "appearance-\(item.rawValue)"
                let chosen = flags.appearance == item
                Button { flags.appearance = item } label: {
                    Text(item.rawValue)
                        .textStyle(Self.choice)
                        .foregroundStyle(chosen ? Theme.text : Theme.text2)
                        .padding(.horizontal, 30)
                        .frame(height: 68)
                        .background(lit ? Theme.amethystSoft : (chosen ? Theme.lit : .clear), in: shape)
                        .overlay(shape.stroke(lit ? Theme.amethyst : .clear, lineWidth: 2))
                        .shadow(color: lit ? Theme.amethyst.opacity(0.35) : .clear, radius: lit ? 24 : 0)
                }
                .buttonStyle(.tvBare)
                .focused($focused, equals: "appearance-\(item.rawValue)")
                .animation(.easeOut(duration: 0.2), value: lit)
            }
        }
        .padding(8)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.line, lineWidth: 1))
    }

    /// The dot is leaf green only while some other device is on the line.
    private var connected: Bool { (devices.syncState?.connectedPeers ?? 0) > 0 }
}

/// Start over on Apple TV: a proper full-screen confirmation with the dialog's words, the two
/// choices as TV rows and the kit's buttons. Menu cancels.
struct TVFreshStartScreen: View {
    let close: () -> Void
    let perform: (_ sample: Bool) -> Void
    @State private var sample = false
    @FocusState private var focused: Focus?

    enum Focus: Hashable { case empty, sample, cancel, erase }

    private static let title = TextStyle(typeface: .display, size: 64, weight: 500)
    private static let body = TextStyle(typeface: .text, size: 28, weight: 400)

    var body: some View {
        VStack(alignment: .leading, spacing: 40) {
            Text(TVSettingsText.startOverTitle)
                .textStyle(Self.title)
                .foregroundStyle(Theme.text)
            Text(FreshStartText.body)
                .textStyle(Self.body)
                .foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 16) {
                TVChoiceRow(on: !sample, title: FreshStartText.emptyTitle, caption: FreshStartText.emptyCaption, lit: focused == .empty) { sample = false }
                    .focused($focused, equals: .empty)
                TVChoiceRow(on: sample, title: FreshStartText.sampleTitle, caption: FreshStartText.sampleCaption, lit: focused == .sample) { sample = true }
                    .focused($focused, equals: .sample)
            }
            Spacer(minLength: 0)
            HStack(spacing: 24) {
                TVKitButton(title: "Cancel", kind: .secondary, lit: focused == .cancel, action: close)
                    .focused($focused, equals: .cancel)
                TVKitButton(title: "Erase and start over", kind: .destructive, lit: focused == .erase) { perform(sample) }
                    .focused($focused, equals: .erase)
                Spacer(minLength: 0)
            }
        }
        .padding(.top, 110)
        .padding(.horizontal, 200)
        .padding(.bottom, 80)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.window.ignoresSafeArea())
        .textRole(.body)
        .foregroundStyle(Theme.text)
        .onExitCommand(perform: close)
        .onAppear { focused = .empty }
    }
}

/// One choice of a TV confirmation: the radio, the title and the caption in a 112 pt row; the
/// chosen one keeps the leaf wash, the focused one the amethyst ring.
struct TVChoiceRow: View {
    let on: Bool
    let title: String
    let caption: String
    let lit: Bool
    let pick: () -> Void

    private static let title = TextStyle(typeface: .text, size: 30, weight: 500)
    private static let caption = TextStyle(typeface: .text, size: 22, weight: 400)

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        Button(action: pick) {
            HStack(spacing: 26) {
                Image(systemName: on ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(on ? Theme.leaf : Theme.text3)
                    .frame(width: 60, height: 60)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .textStyle(Self.title)
                        .foregroundStyle(Theme.text)
                    Text(caption)
                        .textStyle(Self.caption)
                        .foregroundStyle(Theme.text3)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 30)
            .frame(maxWidth: .infinity)
            .frame(height: 112)
            .background(lit ? Theme.amethystSoft : (on ? Theme.leafSoft : Theme.raised), in: shape)
            .overlay(shape.stroke(lit ? Theme.amethyst : (on ? Theme.leaf : Theme.line), lineWidth: lit || on ? 2 : 1))
            .shadow(color: lit ? Theme.amethyst.opacity(0.35) : .clear, radius: lit ? 24 : 0)
        }
        .buttonStyle(.tvBare)
        .animation(.easeOut(duration: 0.2), value: lit)
    }
}
#endif
