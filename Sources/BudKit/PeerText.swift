import Foundation

/// The words and numbers the pairing frames show, kept pure so they test on their own.
public enum PeerText {
    /// How many characters a ticket has.
    public static let ticketLength = 134
    /// How far a typed ticket may be from that and still look like one.
    public static let ticketTolerance = 6

    /// The text without spaces or line breaks.
    private static func squeezed(_ text: String) -> String {
        String(text.filter { !$0.isWhitespace })
    }

    /// Ticket text in groups of five with spaces.
    public static func grouped(_ text: String) -> String {
        let characters = Array(squeezed(text))
        return stride(from: 0, to: characters.count, by: 5)
            .map { String(characters[$0..<min($0 + 5, characters.count)]) }
            .joined(separator: " ")
    }

    /// "37 of 134": the characters typed so far against the length of a ticket.
    public static func typedCount(_ text: String) -> String {
        "\(squeezed(text).count) of \(ticketLength)"
    }

    /// Whether the text starts like a ticket and is about the right length.
    public static func looksLikeTicket(_ text: String) -> Bool {
        let typed = squeezed(text).lowercased()
        return typed.hasPrefix("bud1") && abs(typed.count - ticketLength) <= ticketTolerance
    }

    /// "seen just now", "seen 4 minutes ago", "seen 2 hours ago".
    public static func seen(_ date: Date?, now: Date) -> String {
        guard let date else { return "not seen yet" }
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 { return "seen just now" }
        if seconds < 3600 { return "seen " + ago(seconds / 60, "minute") }
        if seconds < 86400 { return "seen " + ago(seconds / 3600, "hour") }
        return "seen " + ago(seconds / 86400, "day")
    }

    private static func ago(_ count: Int, _ unit: String) -> String {
        "\(count) \(unit)\(count == 1 ? "" : "s") ago"
    }

    /// The time left on a ticket as "9:58"; it never goes below "0:00".
    public static func countdown(until expiresAt: Date, now: Date) -> String {
        let left = max(0, Int(expiresAt.timeIntervalSince(now).rounded(.up)))
        return "\(left / 60):" + (left % 60 < 10 ? "0" : "") + "\(left % 60)"
    }

    /// "k7f3…q2m9": the first four characters, an ellipsis and the last four.
    public static func shortID(_ id: String) -> String {
        guard id.count > 9 else { return id }
        return "\(id.prefix(4))…\(id.suffix(4))"
    }
}
