#if canImport(SwiftUI)
import SwiftUI

/// The whole prototype: the canvas, a trail back to Everything, and a way to add buds by touch.
public struct BudRootView: View {
    @StateObject private var store: BudStore
    @State private var adding: AddTarget? = nil

    @MainActor public init(fileURL: URL? = BudStore.defaultFile) {
        _store = StateObject(wrappedValue: BudStore(fileURL: fileURL))
    }

    public var body: some View {
        OrbitCanvas(store: store)
            .overlay(alignment: .top) { trail }
            .overlay(alignment: .bottom) { hint }
            .sheet(item: $adding) { target in AddSheet(store: store, parent: target.parent) }
            .background(Theme.window)
            .textRole(.body)
            .foregroundStyle(Theme.text)
            .tint(Theme.leaf)
    }

    private var trail: some View {
        HStack(spacing: 6) {
            ForEach(Array(store.centerTrail.enumerated()), id: \.offset) { index, id in
                if index > 0 {
                    Text("›").foregroundStyle(Theme.text3)
                }
                Button(store.tree.title(of: id)) {
                    withAnimation(.spring(duration: 0.8, bounce: 0.12)) { store.center = id }
                }
                .buttonStyle(.plain)
                .textRole(index == store.centerTrail.count - 1 ? .heading : .label)
                .foregroundStyle(index == store.centerTrail.count - 1 ? Theme.leaf : Theme.text2)
            }
            Spacer(minLength: 12)
            Button {
                adding = AddTarget(parent: store.center)
            } label: {
                Label("Add here", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .textRole(.label)
            .tint(Theme.leaf)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.glass, in: RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(Theme.line, lineWidth: 1))
        .padding(12)
    }

    private var hint: some View {
        Text("Drag or scroll to move · pinch to zoom · tap a card with children to center it · tap a leaf to edit · Esc or the trail steps out")
            .textRole(.caption)
            .foregroundStyle(Theme.text3)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Theme.glass, in: Capsule())
            .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
            .padding(12)
    }
}
#endif
