import Foundation

/// A Library trigger: on a schedule, it stamps a copy of a Warehouse template into a place, and
/// logs every firing. Triggers sync through the vault beside the buds; one device fires each.
public struct Trigger: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// The template's title in the Warehouse.
    public var template: String
    /// Where copies go: nil for Everything, else the vault path of the Inbox or a bud.
    public var into: String?
    /// The title of where copies go, for the card when the place is not at hand.
    public var intoName: String
    public var rule: Rule
    public var enabled: Bool
    /// When it was made; nothing before it fires.
    public var created: Date
    /// The device that fires it, and its name for the card. Another device takes over when an
    /// occurrence has waited longer than `grace`.
    public var holder: String?
    public var holderName: String?
    /// The newest firings first, at most `kept`.
    public var log: [Firing]

    public struct Firing: Codable, Hashable, Sendable {
        /// The occurrence it stamped, not when the device got to it.
        public var at: Date
        public var device: String
        /// Why it stamped nothing: the template or the place was gone.
        public var skipped: String?
    }

    public static let kept = 20
    /// How long an occurrence waits for the device that holds the trigger.
    public static let grace: TimeInterval = 3600

    public init(
        id: String = UUID().uuidString, name: String, template: String, into: String?, intoName: String, rule: Rule,
        enabled: Bool = true, created: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.template = template
        self.into = into
        self.intoName = intoName
        self.rule = rule
        self.enabled = enabled
        self.created = created
        log = []
    }

    /// The last occurrence it stamped or skipped; its creation before the first.
    public var lastFired: Date { log.first?.at ?? created }

    /// The occurrence this device should fire now, if any: the latest one due since the last
    /// firing. The holder fires it at once; another device after `grace`, or when there is none.
    public func due(at now: Date, device: String, calendar: Calendar = .current) -> Date? {
        guard enabled, let occurrence = rule.latest(atOrBefore: now, calendar: calendar), occurrence > lastFired else { return nil }
        if holder == nil || holder == device || now.timeIntervalSince(occurrence) >= Self.grace { return occurrence }
        return nil
    }

    /// The trigger after firing `occurrence` on this device.
    public func fired(_ occurrence: Date, device: String, deviceName: String, skipped: String? = nil) -> Trigger {
        var next = self
        next.holder = device
        next.holderName = deviceName
        next.log.insert(Firing(at: occurrence, device: deviceName, skipped: skipped), at: 0)
        if next.log.count > Self.kept { next.log.removeLast(next.log.count - Self.kept) }
        return next
    }

    /// When it fires: every day, every week on a weekday, or every month on a day, at a time.
    public struct Rule: Codable, Hashable, Sendable {
        public enum Every: String, Codable, CaseIterable, Sendable {
            case day, week, month
        }

        public var every: Every
        public var hour: Int
        public var minute: Int
        /// Week: 1 Sunday to 7 Saturday, as `Calendar` counts.
        public var weekday: Int
        /// Month: 1 to 28, so every month has it.
        public var day: Int

        public init(every: Every, hour: Int = 9, minute: Int = 0, weekday: Int = 2, day: Int = 1) {
            self.every = every
            self.hour = hour
            self.minute = minute
            self.weekday = weekday
            self.day = min(max(day, 1), 28)
        }

        private var components: DateComponents {
            var parts = DateComponents(hour: hour, minute: minute)
            switch every {
            case .day: break
            case .week: parts.weekday = weekday
            case .month: parts.day = day
            }
            return parts
        }

        /// The next occurrence after `date`.
        public func next(after date: Date, calendar: Calendar = .current) -> Date? {
            calendar.nextDate(after: date, matching: components, matchingPolicy: .nextTime)
        }

        /// The latest occurrence at or before `date`.
        public func latest(atOrBefore date: Date, calendar: Calendar = .current) -> Date? {
            calendar.nextDate(after: date.addingTimeInterval(1), matching: components, matchingPolicy: .nextTime, direction: .backward)
        }
    }
}

/// The words of a trigger card, kept pure so a test reads them on any platform.
public enum TriggerText {
    /// `Every week → Next Mon 9 Nov → into Routines`.
    public static func rule(_ trigger: Trigger, now: Date, calendar: Calendar = .current) -> String {
        let next = trigger.rule.next(after: now, calendar: calendar).map { "Next \(day($0, calendar: calendar))" } ?? "No next date"
        return "\(every(trigger.rule, calendar: calendar)) → \(next) → into \(trigger.intoName)"
    }

    /// `Every day at 09:00`, `Every week on Monday at 09:00`, `Every month on the 1st at 09:00`.
    public static func every(_ rule: Trigger.Rule, calendar: Calendar = .current) -> String {
        let time = String(format: "%02d:%02d", rule.hour, rule.minute)
        switch rule.every {
        case .day: return "Every day at \(time)"
        case .week:
            let name = weekdays.indices.contains(rule.weekday - 1) ? weekdays[rule.weekday - 1] : "Monday"
            return "Every week on \(name) at \(time)"
        case .month: return "Every month on the \(ordinal(rule.day)) at \(time)"
        }
    }

    /// As `Calendar` counts them, Sunday first.
    public static let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    public static func stamps(_ trigger: Trigger) -> String { "Stamps template \(trigger.template)" }

    /// `Mon 9 Nov 09:00 · on Mac`, or why it stamped nothing.
    public static func firing(_ firing: Trigger.Firing, calendar: Calendar = .current) -> String {
        let when = "\(day(firing.at, calendar: calendar)) \(time(firing.at, calendar: calendar))"
        if let skipped = firing.skipped { return "\(when) · skipped: \(skipped)" }
        return "\(when) · on \(firing.device)"
    }

    static func day(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEE d MMM"
        return formatter.string(from: date)
    }

    static func time(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    static func ordinal(_ n: Int) -> String {
        let suffix: String
        switch (n % 10, n % 100) {
        case (_, 11...13): suffix = "th"
        case (1, _): suffix = "st"
        case (2, _): suffix = "nd"
        case (3, _): suffix = "rd"
        default: suffix = "th"
        }
        return "\(n)\(suffix)"
    }
}
