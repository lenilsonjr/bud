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
            .preferredColorScheme(.dark)
    }

    private var trail: some View {
        HStack(spacing: 6) {
            ForEach(Array(store.centerTrail.enumerated()), id: \.offset) { index, id in
                if index > 0 {
                    Text("›").foregroundStyle(.secondary)
                }
                Button(store.tree.title(of: id)) {
                    withAnimation(.spring(duration: 0.8, bounce: 0.12)) { store.center = id }
                }
                .buttonStyle(.plain)
                .font(index == store.centerTrail.count - 1 ? .headline : .subheadline)
                .foregroundStyle(index == store.centerTrail.count - 1 ? Theme.accent : .secondary)
            }
            Spacer(minLength: 12)
            Button {
                adding = AddTarget(parent: store.center)
            } label: {
                Label("Add here", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .tint(Theme.accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(12)
    }

    private var hint: some View {
        Text("Drag or scroll to move · pinch to zoom · tap a card with children to center it · tap a leaf to edit · Esc or the trail steps out")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(12)
    }
}
#endif
