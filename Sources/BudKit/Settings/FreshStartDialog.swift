#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// Settings › Start over: a dialog that erases every bud on this device and starts again. Two
/// choices, empty or the sample world; the destructive button says what it does. `perform` runs
/// the reset where the store lives and takes the dialog away with it, so the same dialog serves
/// the modal host and the Mac's Settings window; `close` is Cancel alone.
struct FreshStartDialog: View {
    let close: () -> Void
    let perform: (_ sample: Bool) -> Void
    @State private var sample = false

    var body: some View {
        DialogBody(
            title: "Start over on this device?",
            text: FreshStartText.body,
            choices: {
                VStack(spacing: 8) {
                    DialogChoice(on: !sample, title: FreshStartText.emptyTitle, caption: FreshStartText.emptyCaption) { sample = false }
                    DialogChoice(on: sample, title: FreshStartText.sampleTitle, caption: FreshStartText.sampleCaption) { sample = true }
                }
            },
            actions: {
                Button("Cancel", action: close)
                    .buttonStyle(.budSecondary)
                    .keyboardShortcut(.cancelAction)
                Button {
                    perform(sample)
                } label: {
                    BudButtonLabel(title: "Erase and start over")
                }
                .buttonStyle(.budDestructive)
            })
    }
}
#endif

/// The dialog's words, kept pure so a test can read them on any platform.
public enum FreshStartText {
    public static let body = "Every bud on this device goes: the canvas, the files, the Inbox and the Trash. Other devices keep what they hold."
    public static let emptyTitle = "Empty"
    public static let emptyCaption = "Nothing but Everything. Your first capture starts it."
    public static let sampleTitle = "The sample vault"
    public static let sampleCaption = "The newsletter world a first run shows, to look around."
}
