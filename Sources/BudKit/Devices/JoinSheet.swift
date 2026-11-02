#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// Add this device to a vault: a stub for now, with only its title. Typing or scanning a ticket
/// comes with BUD-84, which touches only this file.
struct JoinSheet: View {
    @ObservedObject var devices: DeviceStore
    let close: () -> Void

    private static let title = TextStyle(typeface: .display, size: 24, weight: 500)

    var body: some View {
        Text("Add this \(DevicesText.deviceWord(DevicesText.platform(isPad: DevicesSection.isPad))) to a vault")
            .textStyle(Self.title)
            .foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
