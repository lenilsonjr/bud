#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// Settings: Appearance and the vault folder. A Try section returns whenever two layouts need
/// comparing on a device before one is kept. On the Mac it is the Settings window (⌘,); on iPhone and
/// iPad it is a modal from the gear in the top bar, with Done to close it.
public struct SettingsView: View {
    @ObservedObject private var flags: Flags
    private let onDone: (() -> Void)?

    private static let title = TextStyle(typeface: .display, size: 24, weight: 500)

    public init() {
        self.init(flags: .shared, onDone: nil)
    }

    init(flags: Flags, onDone: (() -> Void)?) {
        self.flags = flags
        self.onDone = onDone
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .textStyle(Self.title)
                .foregroundStyle(Theme.text)
            section("Appearance", caption: "Light and dark follow the system unless you choose one.") {
                Segmented(selection: $flags.appearance, options: Appearance.allCases) { $0.rawValue }
            }
            section("Vault", caption: "Where your buds are kept. A folder of Markdown files is the plan; today it is one file here.") {
                Text(vaultPath)
                    .textRole(.mono)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .foregroundStyle(Theme.text3)
                    .textSelection(.enabled)
            }
            if let onDone {
                HStack {
                    Spacer()
                    Button(action: onDone) { BudButtonLabel(title: "Done") }
                        .buttonStyle(.budPrimary)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .textRole(.body)
        .foregroundStyle(Theme.text)
        .tint(Theme.leaf)
        .frame(minWidth: 360, alignment: .leading)
        .padding(onDone == nil ? 24 : 0)
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
        }
    }
}

extension Appearance {
    /// The scheme to prefer: nil leaves it to the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
#endif
