import Foundation

/// What the source showed of a planted item the last time this device looked: the fields it
/// owns. A field changes in the bud only when it changes here, so a local edit stands until the
/// next change at the source.
public struct SourceSnapshot: Codable, Hashable, Sendable {
    public var title: String
    /// Linear: the team and state the bud's body says.
    public var detail: String?
    public var date: Date?
    public var todo: Bool
    public var cancelled: Bool
    /// When this device saw it.
    public var at: Date?

    public init(_ item: SourceItem, at: Date? = nil) {
        title = item.title
        detail = item.detail
        date = item.date
        todo = item.todo
        cancelled = item.cancelled
        self.at = at
    }

    /// The same values, whenever they were seen.
    func same(as other: SourceSnapshot) -> Bool {
        title == other.title && detail == other.detail && date == other.date && todo == other.todo && cancelled == other.cancelled
    }
}

/// What a device can say about a planted item now.
public enum Sighting: Equatable, Sendable {
    case seen(SourceItem)
    /// Deleted at the source, or no longer readable.
    case gone
}

/// One write that keeps a planted bud live.
public enum LiveChange: Equatable, Sendable {
    case rename(String)
    case when(Date?)
    /// Linear: the issue's due date.
    case due(Date?)
    /// Linear: the body that says the issue's team and state.
    case body(String)
    /// Mail: flagged is an open to-do, unflagged after that is done. Linear and GitHub: completed,
    /// merged or cancelled is done, reopened is open again.
    case state(BudState)
    /// The bud's `from-state`; nil clears it.
    case mark(String?)
}

/// The rules of BUD-103: each source owns some fields of the buds planted from it.
public enum LiveRules {
    /// What to write to a planted bud for what was seen now, and what to remember as seen.
    public static func changes(
        for bud: Bud, kind: SourceKind, sighting: Sighting, last: SourceSnapshot?, now: Date
    ) -> (changes: [LiveChange], seen: SourceSnapshot?) {
        guard case .seen(let item) = sighting else {
            return (bud.fromState == "gone" ? [] : [.mark("gone")], last)
        }
        let seen = SourceSnapshot(item, at: now)
        var changes: [LiveChange] = []
        var mark: String?? = nil
        if bud.fromState == "gone" { mark = .some(nil) }
        guard let last else {
            // First sight: the bud was planted with these values.
            if item.cancelled, bud.fromState != "cancelled" { changes.append(.mark("cancelled")) }
            return (changes, seen)
        }
        // Another device already brought this change in after this one last looked: catch up
        // without writing, so an edit made since then stands.
        if let at = last.at, let since = SourceMark(fromState: bud.fromState)?.at, since > at {
            return ([], seen)
        }
        let stamp = ISO8601DateFormatter().string(from: now)
        if item.title != last.title, item.title != bud.text {
            changes.append(.rename(item.title))
            mark = .some("renamed \(stamp)")
        }
        if kind == .calendar, item.date != last.date {
            changes.append(.when(item.date))
            mark = .some("moved \(stamp)")
        }
        if kind == .linear, item.date != last.date {
            changes.append(.due(item.date))
            mark = .some("moved \(stamp)")
        }
        if kind == .mail, item.todo != last.todo {
            changes.append(.state(item.todo ? .open : .done))
            mark = .some("\(item.todo ? "flagged" : "unflagged") \(stamp)")
        }
        let tracked = kind == .linear || kind == .github
        if item.cancelled != last.cancelled {
            // An issue that went from cancelled to done is closed, not live.
            mark = .some(item.cancelled ? "cancelled" : tracked && !item.todo ? "closed \(stamp)" : nil)
        } else if item.cancelled, bud.fromState != "cancelled" {
            mark = .some("cancelled")
        }
        if tracked {
            // The body follows the state only while it still says what was planted.
            if let detail = item.detail, let was = last.detail, detail != was,
               bud.body.trimmingCharacters(in: .whitespacesAndNewlines) == was {
                changes.append(.body(detail))
            }
            if item.todo != last.todo {
                changes.append(.state(item.todo ? .open : .done))
                mark = .some(item.todo ? "reopened \(stamp)" : item.cancelled ? "cancelled" : "closed \(stamp)")
            }
        }
        if let mark, mark != bud.fromState { changes.append(.mark(mark)) }
        return (changes, seen)
    }
}

extension SourceMark {
    /// The mark a bud's `from-state` carries: `moved 2026-11-05T21:00:00Z`, `cancelled`, `closed`,
    /// `gone`. Nil for none.
    public init?(fromState: String?) {
        guard let text = fromState?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        switch text {
        case "cancelled": self.init(status: .cancelled)
        case "closed": self.init(status: .closed)
        case _ where text.hasPrefix("closed "):
            self.init(status: .closed, at: ISO8601DateFormatter().date(from: String(text.dropFirst(7))))
        case "gone": self.init(status: .gone)
        default:
            let parts = text.split(separator: " ", maxSplits: 1).map(String.init)
            let at = parts.count == 2 ? ISO8601DateFormatter().date(from: parts[1]) : nil
            self.init(status: .changed(parts[0]), at: at)
        }
    }
}
