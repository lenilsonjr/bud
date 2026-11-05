import Foundation

extension SourceAccount {
    /// Made-up accounts for the sample vault, previews and pictures, timed around `now`.
    public static func samples(now: Date = Date()) -> [SourceAccount] {
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        func ahead(_ minutes: Double) -> Date { now.addingTimeInterval(minutes * 60) }
        return [
            SourceAccount(id: "sample-mail", kind: .mail, name: "Mail", items: [
                SourceItem(id: "M-101", title: "Paper samples are ready", detail: "Northside Print", date: ago(12), unread: true),
                SourceItem(id: "M-102", title: "Lease renewal draft", detail: "Harbor Lettings", date: ago(95), unread: true, todo: true),
                SourceItem(id: "M-103", title: "Your order has shipped", detail: "Fieldnote Supply", date: ago(300)),
                SourceItem(id: "M-104", title: "Newsletter name ideas", detail: "Sam", date: ago(1500)),
                SourceItem(id: "M-105", title: "Receipt for October", detail: "Sprout Hosting", date: ago(2900)),
            ]),
            SourceAccount(id: "sample-calendar", kind: .calendar, name: "Calendar", items: [
                SourceItem(id: "E-201", title: "Flat viewing", detail: "Elm Street", date: ahead(45)),
                SourceItem(id: "E-202", title: "Dentist", date: ahead(26 * 60)),
                SourceItem(id: "E-203", title: "Flight to Lisbon", detail: "Gate opens 2h before", date: ahead(5 * 24 * 60)),
            ]),
            SourceAccount(id: "sample-github", kind: .github, name: "GitHub", locked: true),
            SourceAccount(id: "sample-linear", kind: .linear, name: "Linear", items: [
                SourceItem(id: "PRJ-12", title: "Pick the launch date", date: ahead(20 * 60), priority: 2, todo: true),
                SourceItem(id: "PRJ-18", title: "Write the welcome email", priority: 3, todo: true),
            ]),
        ]
    }
}
