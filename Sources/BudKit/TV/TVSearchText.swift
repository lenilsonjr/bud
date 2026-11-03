import Foundation

/// The words of Go anywhere on Apple TV, kept pure so they test on their own.
public enum TVSearchText {
    public static let title = "Go anywhere"
    public static let placeholder = "Type a title"
    public static let phoneKeyboard = "Easier on your iPhone: tap the keyboard notification on it and type there."

    /// The eyebrow over the rows: the recent buds while the field is empty, else the count.
    public static func heading(query: String, hits: Int) -> String {
        if query.trimmingCharacters(in: .whitespaces).isEmpty { return "Recent" }
        switch hits {
        case 0: return "No match"
        case 1: return "1 match"
        default: return "\(hits) matches"
        }
    }

    /// The line where the rows would be when nothing matches.
    public static func empty(query: String) -> String {
        "Nothing is called “\(query.trimmingCharacters(in: .whitespaces))”. Try a shorter word."
    }
}

/// The words of the Apple TV Settings tab, kept pure so they test on their own.
public enum TVSettingsText {
    public static let appearanceCaption = "Bud follows the system until you pick a side."
    public static let startOverCaption = "Erases every bud on this Apple TV and starts again, empty or with the sample vault."
    public static let startOverTitle = "Start over on this Apple TV?"
}
