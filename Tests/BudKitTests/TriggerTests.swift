import XCTest
@testable import BudKit

final class TriggerTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Lisbon")!
        return calendar
    }()
    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }
    private func weekly(created: Date) -> Trigger {
        // 2 is Monday; 9 November 2026 is a Monday.
        Trigger(name: "Monday review", template: "Weekly review", into: nil, intoName: "Everything",
                rule: .init(every: .week, hour: 9, weekday: 2), created: created)
    }

    func testTheRuleFindsTheNextAndTheLatestOccurrence() {
        let rule = Trigger.Rule(every: .week, hour: 9, weekday: 2)
        XCTAssertEqual(rule.next(after: date(6, 12), calendar: calendar), date(9, 9))
        XCTAssertEqual(rule.latest(atOrBefore: date(9, 9), calendar: calendar), date(9, 9), "at the minute counts")
        XCTAssertEqual(rule.latest(atOrBefore: date(10, 8), calendar: calendar), date(9, 9))
        let monthly = Trigger.Rule(every: .month, hour: 8, day: 31)
        XCTAssertEqual(monthly.day, 28, "every month has the day")
        XCTAssertEqual(Trigger.Rule(every: .day, hour: 7, minute: 30).next(after: date(6, 8), calendar: calendar), date(7, 7, 30))
    }

    func testNothingBeforeItWasMadeFiresAndAnOccurrenceFiresOnce() {
        let trigger = weekly(created: date(6, 12))
        XCTAssertNil(trigger.due(at: date(8, 12), device: "mac", calendar: calendar))
        let due = trigger.due(at: date(9, 9, 1), device: "mac", calendar: calendar)
        XCTAssertEqual(due, date(9, 9))
        let fired = trigger.fired(date(9, 9), device: "mac", deviceName: "Mac")
        XCTAssertNil(fired.due(at: date(9, 18), device: "mac", calendar: calendar))
        XCTAssertEqual(fired.due(at: date(16, 9), device: "mac", calendar: calendar), date(16, 9))
    }

    func testMissedOccurrencesFireOnceForTheLatest() {
        let trigger = weekly(created: date(1, 12))
        XCTAssertEqual(trigger.due(at: date(17, 8), device: "mac", calendar: calendar), date(16, 9))
    }

    func testTheHolderFiresAndAnotherDeviceWaitsForTheGrace() {
        let held = weekly(created: date(1, 12)).fired(date(2, 9), device: "mac", deviceName: "Mac")
        XCTAssertNil(held.due(at: date(9, 9, 10), device: "phone", calendar: calendar))
        XCTAssertEqual(held.due(at: date(9, 9, 10), device: "mac", calendar: calendar), date(9, 9))
        XCTAssertEqual(held.due(at: date(9, 10, 1), device: "phone", calendar: calendar), date(9, 9))
        var off = held
        off.enabled = false
        XCTAssertNil(off.due(at: date(9, 10, 1), device: "mac", calendar: calendar))
    }

    func testTheLogKeepsTheNewestFirings() {
        var trigger = weekly(created: date(1, 12))
        for day in 1...25 { trigger = trigger.fired(date(1, 0).addingTimeInterval(Double(day) * 3600), device: "mac", deviceName: "Mac") }
        XCTAssertEqual(trigger.log.count, Trigger.kept)
        XCTAssertGreaterThan(trigger.log[0].at, trigger.log[1].at)
    }

    func testTheCardWords() {
        let trigger = weekly(created: date(1, 12))
        XCTAssertEqual(TriggerText.every(trigger.rule, calendar: calendar), "Every week on Monday at 09:00")
        XCTAssertEqual(TriggerText.rule(trigger, now: date(6, 12), calendar: calendar), "Every week on Monday at 09:00 → Next Mon 9 Nov → into Everything")
        XCTAssertEqual(TriggerText.every(.init(every: .month, hour: 8, day: 22), calendar: calendar), "Every month on the 22nd at 08:00")
        XCTAssertEqual(TriggerText.every(.init(every: .month, hour: 8, day: 11), calendar: calendar), "Every month on the 11th at 08:00")
        XCTAssertEqual(TriggerText.firing(.init(at: date(9, 9), device: "Mac"), calendar: calendar), "Mon 9 Nov 09:00 · on Mac")
        XCTAssertEqual(TriggerText.stamps(trigger), "Stamps template Weekly review")
    }
}
