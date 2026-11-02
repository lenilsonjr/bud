#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// The ticket as text, the way the board draws it: the code in groups of five on a canvas card,
/// and a footer with how long it works, Copy, and Share where the system offers it. The expired
/// variant greys the code and offers Refresh in Copy's place.
struct TicketCodeField: View {
    let text: String
    let status: String
    var expired = false
    var copied = false
    let onCopy: () -> Void
    let onRefresh: () -> Void

    private static let code = TextStyle(typeface: .mono, size: 13, weight: 400)
    private static let footer = TextStyle(typeface: .text, size: 11, weight: 400)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(PeerText.grouped(text))
                .textStyle(Self.code)
                .lineSpacing(13 * 0.65)
                .foregroundStyle(expired ? Theme.text3 : Theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            HStack(spacing: 8) {
                Image(systemName: expired ? "clock.badge.xmark" : "timer")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.text3)
                Text(status)
                    .textStyle(Self.footer)
                    .foregroundStyle(Theme.text3)
                    .monospacedDigit()
                Spacer(minLength: 8)
                if expired {
                    Button(action: onRefresh) { BudButtonLabel(title: "Refresh", systemImage: "arrow.clockwise") }
                        .buttonStyle(.budPrimary)
                } else {
                    Button(action: onCopy) { BudButtonLabel(title: copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc") }
                        .buttonStyle(.budSecondary)
                    #if os(iOS)
                    ShareLink(item: text) { BudButtonLabel(title: "Share", systemImage: "square.and.arrow.up") }
                        .buttonStyle(.budSecondary)
                    #endif
                }
            }
        }
        .padding(14)
        .background(Theme.canvas, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).stroke(Theme.lineStrong, lineWidth: 1))
    }
}
#endif
