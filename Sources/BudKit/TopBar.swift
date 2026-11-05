#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// One bar across the top of the window: the mark, Canvas | Files, where you are, the next
/// step, Go anywhere, the zoom and Capture. On the Mac it leaves room for the window controls
/// and drags the window.
struct TopBar: View {
    @ObservedObject var store: BudStore
    let onAdd: () -> Void
    let onSearch: () -> Void
    @Environment(\.compact) private var compact
    @Environment(\.stillPicture) private var still
    @State private var lensOpen = false

    var body: some View {
        HStack(spacing: compact ? 10 : 14) {
            #if os(iOS)
            if !compact && store.surface == .files { sidebarToggle }
            #endif
            Image(systemName: "leaf.fill")
                .textRole(.heading)
                .foregroundStyle(Theme.leaf)
            Segmented(selection: $store.surface, options: Surface.allCases) { $0.rawValue }
            if compact {
                // The place name takes whatever the buttons leave, so it never clips early.
                lastCrumb.frame(maxWidth: .infinity, alignment: .leading)
            } else {
                breadcrumb.layoutPriority(1)
                if store.surface == .canvas && !store.canvasFacets.isEmpty { lensChips }
                Spacer(minLength: 8)
            }
            if compact {
                if let step = store.nextStep { bullseye(step.bud) }
                Button(action: onSearch) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Theme.text2)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Go anywhere")
                .accessibilityLabel("Go anywhere")
                if store.surface == .canvas { lensMenu }
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .foregroundStyle(Theme.text)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Capture")
                .accessibilityLabel("Capture")
            } else {
                if store.surface == .canvas { lensMenu }
                if let step = store.nextStep { nextStep(step.bud, elsewhere: step.elsewhere) }
                #if os(macOS)
                SyncDot(devices: store.devices)
                #endif
                goAnywhere
                if store.surface == .canvas { zoom }
                Button(action: onAdd) {
                    BudButtonLabel(title: "Capture", systemImage: "plus")
                }
                .buttonStyle(.budSecondary)
            }
            #if os(iOS)
            Button { store.modal = .settings } label: {
                Image(systemName: "gearshape")
                    .foregroundStyle(Theme.text2)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                    .overlay(alignment: .topTrailing) { SyncBadge(devices: store.devices).offset(x: 1, y: -3) }
            }
            .buttonStyle(.plain)
            .help("Settings")
            .accessibilityLabel("Settings")
            #endif
        }
        .task { await store.devices.start() }
        .padding(.leading, compact ? 12 : leadingInset)
        .padding(.trailing, compact ? 8 : 14)
        .frame(height: 52)
        .frame(maxWidth: .infinity)
        .background(Theme.window)
        .overlay(alignment: .bottom) { Theme.line.frame(height: 1) }
        #if os(macOS)
        .background(WindowDragArea())
        #endif
    }

    #if os(iOS)
    /// Shows or collapses the Files sidebar.
    private var sidebarToggle: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) { store.sidebar.toggle(in: store.surfaceSize) }
        } label: {
            Image(systemName: "sidebar.left")
                .foregroundStyle(Theme.text2)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Show or hide the sidebar")
        .accessibilityLabel("Show or hide the sidebar")
    }
    #endif

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

    /// On a phone, only where you are: the last crumb, or the place.
    private var lastCrumb: some View {
        Text(placeName ?? store.tree.title(of: store.center))
            .textRole(.label)
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(Theme.text)
    }

    /// The next step on a phone: the bullseye alone jumps to it.
    private func bullseye(_ bud: Bud) -> some View {
        Button {
            withAnimation(.spring(duration: 0.8, bounce: 0.12)) { store.center = bud.id }
        } label: {
            Image(systemName: "scope")
                .foregroundStyle(Theme.leaf)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Next step: \(Self.shortTitle(bud.text))")
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
        .background(RoundedRectangle(cornerRadius: Radius.button).stroke(Theme.leafLine, lineWidth: 1))
        #if os(iOS)
        // On an iPad the pill keeps its label ahead of the breadcrumb and the rest of the bar.
        .layoutPriority(2)
        #endif
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
                    .lineLimit(1)
                Spacer(minLength: 0)
                #if os(macOS)
                Keycap("⌘K")
                #endif
            }
            .textRole(.label)
            .padding(.leading, 10)
            .padding(.trailing, 5)
            .padding(.vertical, 5)
            #if os(iOS)
            // On an iPad the field gives way before the pill's label does, down to the width that
            // keeps its placeholder on one line; the keycap is the Mac's, where ⌘K is the way in.
            .frame(minWidth: 124, maxWidth: 180)
            #else
            .frame(width: 180)
            #endif
            .background(Theme.sidebar, in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).stroke(Theme.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Ask the canvas a question: tick rows in the lens menu and the hits stay lit, the path to
    /// them half lit, the rest fades, while the menu is still open. The picture renderer cannot
    /// draw a popover, so a still picture shows the button alone.
    @ViewBuilder private var lensMenu: some View {
        Button { lensOpen.toggle() } label: { lensLabel }
            .buttonStyle(.plain)
            .fixedSize()
            .help("Light up what matches")
            .accessibilityLabel(lensSpoken)
            .accessibilityIdentifier("canvas-lens")
            .popover(isPresented: still ? .constant(false) : $lensOpen, arrowEdge: .bottom) {
                LensMenu(store: store)
                #if os(iOS)
                .presentationCompactAdaptation(.popover)
                #endif
            }
    }

    private var nothingMatches: Bool { store.canvasLens != nil && store.canvasLight.isEmpty }

    private var lensSpoken: String {
        let count = store.canvasFacets.count
        guard count > 0 else { return "Lens" }
        let names = store.canvasFacets.map(\.name).joined(separator: ", ")
        return "Lens: \(names)" + (nothingMatches ? ", no matches" : "")
    }

    /// On a narrow bar a bare glyph like the search glass beside it, filled while a lens is on;
    /// elsewhere "Lens" with how many rows are ticked, filled in leaf while a lens is on.
    @ViewBuilder private var lensLabel: some View {
        let on = !store.canvasFacets.isEmpty
        if compact {
            Image(systemName: on ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                .foregroundStyle(on ? (nothingMatches ? Theme.text3 : Theme.leaf) : Theme.text2)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        } else {
            let shape = RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease")
                Text("Lens")
                if on {
                    Text("\(store.canvasFacets.count)")
                        .textRole(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.leaf)
                        .padding(.horizontal, 5)
                        .background(Theme.onLeaf, in: Capsule())
                }
            }
            .textRole(.label)
            .foregroundStyle(on ? Theme.onLeaf : Theme.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(on ? Theme.leaf : Theme.glass, in: shape)
            .overlay(shape.stroke(on ? Theme.leaf : Theme.lineStrong, lineWidth: 1))
            .contentShape(shape)
        }
    }

    /// The lens as chips after the breadcrumb, each with × to untick it.
    private var lensChips: some View {
        HStack(spacing: 6) {
            ForEach(store.canvasFacets, id: \.self) { facet in
                HStack(spacing: 4) {
                    Text(facet.name)
                        .textRole(.label)
                        .foregroundStyle(Theme.leaf)
                    Button {
                        withAnimation(.easeOut(duration: 0.35)) { store.canvasFacets.removeAll { $0 == facet } }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Theme.leaf)
                            .frame(width: 14, height: 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(facet.name) from the lens")
                }
                .padding(.leading, 8)
                .padding(.trailing, 4)
                .padding(.vertical, 3)
                .background(Theme.leafSoft, in: Capsule())
                .overlay(Capsule().stroke(Theme.leafLine, lineWidth: 1))
            }
        }
        .fixedSize()
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
        .background(Theme.glass, in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.button, style: .continuous).stroke(Theme.lineStrong, lineWidth: 1))
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
            .overlay(RoundedRectangle(cornerRadius: Radius.keycap, style: .continuous).stroke(Theme.lineStrong, lineWidth: 1))
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
