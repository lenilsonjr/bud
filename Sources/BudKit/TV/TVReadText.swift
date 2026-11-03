import Foundation

/// The words of the Apple TV read screen, kept pure so they test on their own.
public enum TVReadText {
    /// The line under the title: the one open to-do to do next inside the bud, or nothing.
    public static func nextStep(in tree: Tree, under id: UUID) -> String? {
        guard let step = tree.nextStep(under: id), step.id != id else { return nil }
        return "Next: \(step.text)"
    }

    /// What Play/Pause does on the screen: closes the next step, or the bud itself when it is
    /// an open to-do with nothing open inside, or nothing.
    public static func playPauseHint(in tree: Tree, under id: UUID) -> String? {
        guard let bud = tree.bud(id) else { return nil }
        if let step = tree.nextStep(under: id), step.id != id { return "Play/Pause closes \(step.text)" }
        if bud.isTodo, !bud.isDone { return "Play/Pause closes this to-do" }
        return nil
    }

    /// The eyebrow over the children: "4 inside · 5 open", or "Nothing inside yet".
    public static func insideLine(in tree: Tree, under id: UUID) -> String {
        let count = tree.children(of: id).count
        guard count > 0 else { return "Nothing inside yet" }
        let open = tree.openCount(under: id)
        return "\(count) inside" + (open > 0 ? " · \(open) open" : "")
    }

    /// The kind and dates under the title: "To-do · Due 3 Nov", "Note", "Done".
    public static func kindLine(_ bud: Bud) -> String {
        var parts = [bud.isTodo ? (bud.isDone ? "Done" : "To-do") : "Note"]
        if let due = bud.due { parts.append("Due \(short(due))") }
        if let when = bud.when { parts.append("Scheduled \(short(when))") }
        if bud.pinned { parts.append("Pinned") }
        return parts.joined(separator: " · ")
    }

    private static func short(_ date: Date) -> String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("d MMM")
        return f.string(from: date)
    }
}
