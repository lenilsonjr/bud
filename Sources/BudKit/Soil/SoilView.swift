#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// The band under the canvas where sources show, each account a root under the soil line with
/// what needs you soonest nearest it. Folded, the roots become a strip of chips. An item dragged
/// up through the line is planted where it lands; nothing here is written before that.
struct SoilView: View {
    let roots: [Root]
    /// The moment the roots were read at, so the leaf dots agree with them.
    let now: Date
    let folded: Bool
    /// The device word for a locked root: "Sign in on this Mac".
    let device: String
    let onFold: () -> Void
    /// Signs this device in to a locked account.
    var onSignIn: (String) -> Void = { _ in }
    /// An item in hand, at a point in the canvas's space; nil when it is let go.
    let onDrag: (SourceItem, SourceAccount, CGPoint) -> Void
    let onDrop: (SourceItem, SourceAccount, CGPoint) -> Void
    /// The grip let go, dropped or cancelled: a cancelled drag never reaches `onDrop`.
    var onRelease: () -> Void = {}
    @GestureState private var holding = false

    static let openHeight: CGFloat = 236
    static let foldedHeight: CGFloat = 52
    static let rootWidth: CGFloat = 208
    static let space = "orbit"

    var body: some View {
        VStack(spacing: 0) {
            line
            if folded { strip } else { band }
        }
        .frame(height: folded ? Self.foldedHeight : Self.openHeight, alignment: .top)
        .frame(maxWidth: .infinity)
        .background(Theme.sidebar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("soil")
        .onChange(of: holding) { _, now in if !now { onRelease() } }
    }

    /// The soil line, with the handle that folds and opens the roots.
    private var line: some View {
        ZStack {
            Rectangle().fill(Theme.lineStrong).frame(height: 1)
            Button(action: onFold) {
                HStack(spacing: 6) {
                    Text("Soil").textRole(.label)
                    Image(systemName: folded ? "chevron.up" : "chevron.down").font(.system(size: 10, weight: .semibold))
                    #if os(macOS)
                    Keycap(Keys.key(for: .soil).label).accessibilityHidden(true)
                    #endif
                }
                .foregroundStyle(Theme.text2)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Theme.raised, in: Capsule())
                .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(Keys.shortcut(.soil))
            .accessibilityLabel(folded ? "Open the soil" : "Fold the soil")
            .accessibilityIdentifier("soil-handle")
        }
        .frame(height: 28)
    }

    private var band: some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach(roots) { root in
                column(root)
            }
        }
        .padding(.top, 8)
        .padding(.horizontal, 16)
    }

    private func column(_ root: Root) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            header(root)
            if root.account.locked {
                Button { onSignIn(root.id) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                        Text("Sign in on this \(device)")
                    }
                }
                .buttonStyle(.plain)
                .textRole(.caption)
                .foregroundStyle(Theme.text3)
                .padding(.top, 4)
            } else {
                ForEach(root.items) { item in
                    row(item, in: root.account)
                }
                if root.more > 0 {
                    Text("\(root.more) more below")
                        .textRole(.caption)
                        .foregroundStyle(Theme.text3)
                        .accessibilityIdentifier("soil-more-\(root.id)")
                }
            }
        }
        .frame(width: Self.rootWidth, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("root-\(root.id)")
    }

    private func header(_ root: Root) -> some View {
        HStack(spacing: 6) {
            Image(systemName: Self.symbol(root.account.kind))
            Text(root.account.name).textRole(.eyebrow)
            Spacer(minLength: 0)
            if !root.account.locked {
                Text("\(root.count)").textRole(.caption).monospacedDigit()
            }
        }
        .foregroundStyle(Theme.text2)
    }

    private func row(_ item: SourceItem, in account: SourceAccount) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if Root.needsYou(item, kind: account.kind, now: now) {
                    Circle().fill(Theme.leaf).frame(width: 6, height: 6)
                }
                Text(item.title).textRole(.cardTitle).foregroundStyle(Theme.cardInk).lineLimit(1)
            }
            if let detail = item.detail {
                Text(detail).textRole(.caption).foregroundStyle(Theme.cardMeta).lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(width: Self.rootWidth, alignment: .leading)
        .background(Theme.card, in: shape)
        .overlay(shape.stroke(Theme.cardLine, lineWidth: 1))
        .contentShape(shape)
        .gesture(
            DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.space))
                .updating($holding) { _, state, _ in state = true }
                .onChanged { onDrag(item, account, $0.location) }
                .onEnded { onDrop(item, account, $0.location) }
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("soil-item-\(item.id)")
    }

    private var strip: some View {
        HStack(spacing: 10) {
            ForEach(roots) { root in
                chip(root)
            }
        }
        .padding(.top, 2)
    }

    private func chip(_ root: Root) -> some View {
        HStack(spacing: 6) {
            Image(systemName: Self.symbol(root.account.kind))
            Text(root.account.name).textRole(.label)
            if root.account.locked {
                Image(systemName: "lock.fill").font(.system(size: 9))
            } else {
                Text("\(root.count)").textRole(.caption).monospacedDigit()
                if root.leaf {
                    Circle().fill(Theme.leaf).frame(width: 6, height: 6).accessibilityLabel("Needs you")
                }
            }
        }
        .foregroundStyle(Theme.text2)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Theme.raised, in: Capsule())
        .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("soil-chip-\(root.id)")
    }

    static func symbol(_ kind: SourceKind) -> String {
        switch kind {
        case .mail: return "envelope"
        case .calendar: return "calendar"
        case .github: return "chevron.left.forwardslash.chevron.right"
        case .linear: return "checklist"
        }
    }
}
#endif
