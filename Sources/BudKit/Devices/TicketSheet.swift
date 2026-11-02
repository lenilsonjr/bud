#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// Show a ticket: a stub for now, with only its title. The ticket and its QR code come with BUD-83,
/// which touches only this file.
struct TicketSheet: View {
    @ObservedObject var devices: DeviceStore
    let close: () -> Void

    private static let title = TextStyle(typeface: .display, size: 24, weight: 500)

    var body: some View {
        Text("Show a ticket")
            .textStyle(Self.title)
            .foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
