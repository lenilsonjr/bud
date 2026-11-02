#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// Close branch (F1): a to-do with open to-dos inside can close and leave them open, or close
/// them too. Closing never cascades on its own; this is where you are asked. Esc cancels,
/// Return closes.
struct CloseBranchDialog: View {
    @ObservedObject var store: BudStore
    let id: UUID
    @State private var cascade = false

    private static let title = TextStyle(typeface: .display, size: 24, weight: 500)
    private static let body = TextStyle(typeface: .text, size: 13, weight: 400)

    var body: some View {
        let open = store.tree.openCount(under: id)
        VStack(alignment: .leading, spacing: 16) {
            Text("Close \(store.tree.title(of: id))?")
                .textStyle(Self.title)
                .foregroundStyle(Theme.text)
            Text("It has \(open) open \(open == 1 ? "to-do" : "to-dos") inside. Notes, links and closed items stay as they are. Closing never cascades on its own.")
                .textStyle(Self.body)
                .lineSpacing(13 * 0.5)
                .foregroundStyle(Theme.text2)
            VStack(spacing: 8) {
                choice(cascade: false, title: "Leave the \(open) \(open == 1 ? "to-do" : "to-dos") open", caption: "They stay findable in Today and To-dos.")
                choice(cascade: true, title: "Close them too", caption: "Marks every open to-do inside as done.")
            }
            HStack(spacing: 8) {
                Spacer()
                Button { store.modal = nil } label: { BudButtonLabel(title: "Cancel") }
                    .buttonStyle(.budSecondary)
                    .keyboardShortcut(.cancelAction)
                Button(action: close) { BudButtonLabel(title: "Close branch") }
                    .buttonStyle(.budDestructive)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .textRole(.body)
        .tint(Theme.leaf)
    }

    /// A radio row drawn in SwiftUI: the ring at the left, a title and a caption.
    private func choice(cascade value: Bool, title: String, caption: String) -> some View {
        let on = cascade == value
        let shape = RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
        return Button {
            cascade = value
        } label: {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle().stroke(on ? Theme.leaf : Theme.text3, lineWidth: 1.5)
                    if on { Circle().fill(Theme.leaf).padding(4) }
                }
                .frame(width: 16, height: 16)
                .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .textRole(.cardTitle)
                        .foregroundStyle(Theme.text)
                    Text(caption)
                        .textRole(.caption)
                        .foregroundStyle(Theme.text3)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(on ? Theme.leafSoft : .clear, in: shape)
            .overlay(shape.stroke(on ? Theme.leafLine : Theme.line, lineWidth: on ? 1.5 : 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
    }

    private func close() {
        store.close(id, cascade: cascade)
        store.modal = nil
    }
}
#endif
