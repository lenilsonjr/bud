import Foundation

/// The measures every kit button shares: a 13 pt semibold label, an optional 14 pt icon before it.
enum ButtonMetrics {
    static let cornerRadius: CGFloat = Radius.button
    static let verticalPadding: CGFloat = 7
    static let horizontalPadding: CGFloat = 12
    static let iconSize: CGFloat = 14
    static let labelSize: CGFloat = 13
    static let pressedOpacity: Double = 0.85
}

#if canImport(SwiftUI)
import SwiftUI

/// The four kit buttons: primary, secondary, ghost and destructive.
struct BudButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, ghost, destructive }
    let kind: Kind

    private var fill: Color {
        switch kind {
        case .primary: return Theme.leafFill
        case .secondary: return Theme.raised
        case .ghost: return Theme.leafSoft
        case .destructive: return Theme.roseSoft
        }
    }

    private var ink: Color {
        switch kind {
        case .primary: return Theme.onLeaf
        case .secondary: return Theme.text
        case .ghost: return Theme.leaf
        case .destructive: return Theme.rose
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: ButtonMetrics.cornerRadius, style: .continuous)
        return configuration.label
            .textRole(.cardTitle)
            .foregroundStyle(ink)
            .padding(.vertical, ButtonMetrics.verticalPadding)
            .padding(.horizontal, ButtonMetrics.horizontalPadding)
            .background(fill, in: shape)
            .overlay { if kind == .secondary { shape.stroke(Theme.lineStrong, lineWidth: 1) } }
            .contentShape(shape)
            .opacity(configuration.isPressed ? ButtonMetrics.pressedOpacity : 1)
    }
}

extension ButtonStyle where Self == BudButtonStyle {
    static var budPrimary: BudButtonStyle { BudButtonStyle(kind: .primary) }
    static var budSecondary: BudButtonStyle { BudButtonStyle(kind: .secondary) }
    static var budGhost: BudButtonStyle { BudButtonStyle(kind: .ghost) }
    static var budDestructive: BudButtonStyle { BudButtonStyle(kind: .destructive) }
}

/// A button label with the 14 pt icon before the text.
struct BudButtonLabel: View {
    let title: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: ButtonMetrics.iconSize, height: ButtonMetrics.iconSize)
            }
            Text(title)
        }
    }
}
#endif
