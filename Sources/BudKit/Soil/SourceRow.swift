#if canImport(SwiftUI)
import SwiftUI

/// A planted bud's source row on its card: the source and how the bud stands with it.
struct SourceRow: View {
    let from: String
    let mark: SourceMark?
    /// The ink of a live row: the card's own meta colour.
    let fallback: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let status = SourceRowText.status(mark, now: context.date)
            HStack(spacing: 4) {
                Image(systemName: Self.symbol(status))
                Text(SourceRowText.card(from: from, mark: mark, now: context.date))
                    .lineLimit(1)
            }
            .textRole(.caption)
            .foregroundStyle(Self.ink(status, fallback: fallback))
            .accessibilityIdentifier("source-row")
        }
    }

    static func symbol(_ status: SourceMark.Status) -> String {
        switch status {
        case .live: return "dot.radiowaves.left.and.right"
        case .changed: return "arrow.triangle.2.circlepath"
        case .closed: return "checkmark.circle"
        case .cancelled: return "xmark.circle"
        case .gone: return "questionmark.circle"
        }
    }

    static func ink(_ status: SourceMark.Status, fallback: Color) -> Color {
        switch status {
        case .live, .closed: return fallback
        case .changed: return Theme.leaf
        case .cancelled, .gone: return Theme.rose
        }
    }
}

/// "from Linear" beside a field the source owns.
struct FromMark: View {
    let from: String

    var body: some View {
        Text("from \(SourceRowText.name(from))")
            .textRole(.caption)
            .foregroundStyle(Theme.text3)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Theme.surface, in: Capsule())
            .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
    }
}

/// The source row at the top of a planted bud's page: the source and item id, the last sync and
/// the device that ran it, and "Open in …" when the item has an address. Read-only on TV.
struct SourcePageRow: View {
    let from: String
    let mark: SourceMark?
    @Environment(\.openURL) private var openURL

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(SourceRowText.title(from: from))
                        .textRole(.label)
                        .foregroundStyle(Theme.text)
                    HStack(spacing: 6) {
                        SourceRow(from: from, mark: mark, fallback: Theme.text2)
                        Text("·").textRole(.caption).foregroundStyle(Theme.text3)
                        Text(SourceRowText.synced(mark, now: context.date))
                            .textRole(.caption)
                            .foregroundStyle(Theme.text3)
                    }
                }
                #if !os(tvOS)
                if let url = mark?.url {
                    Button(SourceRowText.open(from: from)) { openURL(url) }
                        .buttonStyle(.bordered)
                        .textRole(.label)
                }
                #endif
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("source-page-row")
        }
    }
}
#endif
