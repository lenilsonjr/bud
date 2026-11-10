import Foundation

/// A day the short way rows write it: "3 Nov", in the calendar's locale.
public enum DayText {
    public static func short(_ date: Date, calendar: Calendar = .current) -> String {
        formatter(template: "d MMM", calendar: calendar).string(from: date)
    }

    /// A date as the vault files write `when` and `due`: the day, `2026-11-04`, when it is
    /// midnight in the calendar; the moment with its zone, `2026-11-03T14:00:00+01:00`, when it
    /// has a time of day, so its first ten characters still name the day it was set on. The
    /// core keeps either as written and counts a moment on its day.
    public static func fileDate(_ date: Date, calendar: Calendar = .current) -> String {
        if calendar.startOfDay(for: date) == date {
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        }
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = calendar.timeZone
        return formatter.string(from: date)
    }

    /// One formatter per template, calendar, time zone and locale, kept: a board of cards asks
    /// for the same few on every render, and a formatter is slow to make.
    static func formatter(template: String, calendar: Calendar) -> DateFormatter {
        let locale = calendar.locale ?? .current
        let key = "\(template)|\(calendar.identifier)|\(calendar.timeZone.identifier)|\(locale.identifier)"
        return formatters.formatter(for: key) {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.locale = locale
            formatter.setLocalizedDateFormatFromTemplate(template)
            return formatter
        }
    }

    /// A formatter with the format written out, for a title whose shape must be the same on
    /// every platform: a localized template places its commas by the platform's tables.
    static func formatter(format: String, calendar: Calendar) -> DateFormatter {
        let locale = calendar.locale ?? .current
        let key = "=\(format)|\(calendar.identifier)|\(calendar.timeZone.identifier)|\(locale.identifier)"
        return formatters.formatter(for: key) {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.locale = locale
            formatter.dateFormat = format
            return formatter
        }
    }

    private static let formatters = FormatterCache()

    private final class FormatterCache: @unchecked Sendable {
        private var kept: [String: DateFormatter] = [:]
        private let lock = NSLock()

        func formatter(for key: String, make: () -> DateFormatter) -> DateFormatter {
            lock.lock()
            defer { lock.unlock() }
            if let formatter = kept[key] { return formatter }
            let formatter = make()
            kept[key] = formatter
            return formatter
        }
    }
}
