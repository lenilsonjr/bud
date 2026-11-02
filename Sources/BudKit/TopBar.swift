#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// One bar across the top of the window: the mark, Canvas | Files, where you are, the next
/// step, Go anywhere, the zoom and Add here. On the Mac it leaves room for the window controls
/// and drags the window.
struct TopBar: View {
    @ObservedObject var store: BudStore
    let onAdd: () -> Void
    let onSearch: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "leaf.fill")
                .textRole(.heading)
                .foregroundStyle(Theme.leaf)
            Segmented(selection: $store.surface, options: Surface.allCases) { $0.rawValue }
            breadcrumb
                .layoutPriority(1)
            Spacer(minLength: 8)
            if let step = store.nextStep { nextStep(step.bud, elsewhere: step.elsewhere) }
            goAnywhere
            if store.surface == .canvas { zoom }
            Button(action: onAdd) {
                BudButtonLabel(title: "Add here", systemImage: "plus")
            }
            .buttonStyle(.budSecondary)
            #if os(iOS)
            Button { store.modal = .settings } label: {
                Image(systemName: "gearshape")
                    .foregroundStyle(Theme.text2)
            }
            .buttonStyle(.plain)
            .help("Settings")
            #endif
        }
        .padding(.leading, leadingInset)
        .padding(.trailing, 14)
        .frame(height: 52)
        .frame(maxWidth: .infinity)
        .background(Theme.window)
        .overlay(alignment: .bottom) { Theme.line.frame(height: 1) }
        #if os(macOS)
        .background(WindowDragArea())
        #endif
    }

    /// Room for the traffic lights on the Mac; the design's own inset elsewhere.
    private var leadingInset: CGFloat {
        #if os(macOS)
        return 78
        #else
        return 18
        #endif
    }

    /// The lens or the Inbox when Files shows one instead of the center's page.
    private var placeName: String? {
        guard store.surface == .files else { return nil }
        return store.place?.rawValue ?? store.lens?.rawValue
    }

    private var breadcrumb: some View {
        HStack(spacing: 5) {
            ForEach(Array(store.centerTrail.enumerated()), id: \.offset) { index, id in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .textRole(.caption)
                        .foregroundStyle(Theme.text3)
                }
                Button(store.tree.title(of: id)) {
                    withAnimation(.spring(duration: 0.8, bounce: 0.12)) { store.center = id }
                }
                .buttonStyle(.plain)
                .textRole(.label)
                .foregroundStyle(index == store.centerTrail.count - 1 && placeName == nil ? Theme.text : Theme.text2)
            }
            if let placeName {
                Image(systemName: "chevron.right")
                    .textRole(.caption)
                    .foregroundStyle(Theme.text3)
                Text(placeName)
                    .textRole(.label)
                    .foregroundStyle(Theme.text)
            }
        }
        .lineLimit(1)
    }

    /// The next step: the bullseye jumps to it in the current view, Done closes it from here.
    private func nextStep(_ bud: Bud, elsewhere: Bool) -> some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.spring(duration: 0.8, bounce: 0.12)) { store.center = bud.id }
            } label: {
                Image(systemName: "scope")
                    .foregroundStyle(Theme.leaf)
            }
            .buttonStyle(.plain)
            .help("Go to it")
            if elsewhere {
                Text("ELSEWHERE")
                    .textRole(.eyebrow)
                    .foregroundStyle(Theme.text3)
            }
            Button(Self.shortTitle(bud.text)) {
                withAnimation(.spring(duration: 0.8, bounce: 0.12)) { store.center = bud.id }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.text)
            .lineLimit(1)
            Button("Done") { store.tick(bud.id) }
                .buttonStyle(.budGhost)
                .padding(.leading, 0)
        }
        .textRole(.label)
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: Radius.lg).stroke(Theme.leafLine, lineWidth: 1))
    }

    /// The next step's title, cut at 28 characters with an ellipsis so the pill keeps its shape.
    static func shortTitle(_ text: String, limit: Int = 28) -> String {
        text.count > limit ? String(text.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…" : text
    }

    private var goAnywhere: some View {
        Button(action: onSearch) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.text3)
                Text("Go anywhere")
                    .foregroundStyle(Theme.text3)
                Spacer(minLength: 0)
                Keycap("⌘K")
            }
            .textRole(.label)
            .padding(.leading, 10)
            .padding(.trailing, 5)
            .padding(.vertical, 5)
            .frame(width: 180)
            .background(Theme.sidebar, in: RoundedRectangle(cornerRadius: Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Theme.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var zoom: some View {
        Button("\(Int((store.zoom * 100).rounded()))%") {
            withAnimation(.spring(duration: 0.5, bounce: 0)) { store.zoom = 1 }
        }
        .buttonStyle(.plain)
        .textRole(.label)
        .foregroundStyle(Theme.text2)
        .monospacedDigit()
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Theme.glass, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.lineStrong, lineWidth: 1))
        .help("Back to 100%")
    }
}

/// A key the way the board draws it: a small rounded tile with the shortcut in it.
struct Keycap: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Theme.font(TextStyle(typeface: .mono, size: 10, weight: 500)))
            .foregroundStyle(Theme.text3)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(Theme.lineStrong, lineWidth: 1))
    }
}

#if os(macOS)
import AppKit

/// Lets the bar move the window, the way a title bar would.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {}

    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}
#endif
#endif
