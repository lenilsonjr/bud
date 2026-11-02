#if canImport(SwiftUI) && os(macOS)
import SwiftUI

/// The face of the ⌥Space panel: one line, the kind, where it came from, Return to capture and
/// Esc to close. The AppKit panel around it lives in the app.
public struct CapturePanelView: View {
    let from: String?
    let onCapture: (CaptureRelay.Line) -> Void
    let onClose: () -> Void
    @State private var text = ""
    @State private var todo = false
    @FocusState private var typing: Bool

    public static let size = CGSize(width: 520, height: 150)

    public init(from: String?, onCapture: @escaping (CaptureRelay.Line) -> Void, onClose: @escaping () -> Void) {
        self.from = from
        self.onCapture = onCapture
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "leaf.fill")
                    .foregroundStyle(Theme.leaf)
                TextField("Capture a thought", text: $text)
                    .textFieldStyle(.plain)
                    .textRole(.heading)
                    .foregroundStyle(Theme.text)
                    .focused($typing)
                    .onSubmit(capture)
                Keycap("esc")
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(typing ? Theme.leafLine : Theme.lineStrong, lineWidth: 1))
            HStack(spacing: 12) {
                Text("Kind")
                    .textRole(.label)
                    .foregroundStyle(Theme.text2)
                Segmented(selection: $todo, options: [false, true]) { $0 ? "To-do" : "Note" }
                Spacer()
                Text(from.map { "Lands in the Inbox · from \($0)" } ?? "Lands in the Inbox")
                    .textRole(.caption)
                    .foregroundStyle(Theme.text3)
                    .lineLimit(1)
            }
        }
        .padding(16)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Theme.line, lineWidth: 1))
        .shadow(color: Theme.shadowStrong, radius: 24, y: 12)
        .textRole(.body)
        .foregroundStyle(Theme.text)
        .tint(Theme.leaf)
        .onAppear { text = ""; todo = false; typing = true }
        .onExitCommand(perform: onClose)
    }

    private func capture() {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        onCapture(CaptureRelay.Line(text: line, todo: todo, from: from))
        text = ""
        onClose()
    }
}
#endif
