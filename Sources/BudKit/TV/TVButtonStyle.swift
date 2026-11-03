#if canImport(SwiftUI) && os(tvOS)
import SwiftUI

/// A button that draws nothing of its own on Apple TV. The system's built-in styles, `.plain`
/// among them, put a white platter with lift and shadow around a focused button, and
/// `focusEffectDisabled()` does not take that away. A custom style gets no platter at all, so
/// every TV control draws its own focus look: the soft amethyst glow, with no lift.
struct TVBareButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? ButtonMetrics.pressedOpacity : 1)
    }
}

extension ButtonStyle where Self == TVBareButtonStyle {
    static var tvBare: TVBareButtonStyle { TVBareButtonStyle() }
}


/// The kit's button at TV size: 84 pt tall, primary in leaf, secondary raised, destructive in
/// the rose wash; the focus look is the amethyst ring and glow, drawn here, never lifted.
struct TVKitButton: View {
    enum Kind { case primary, secondary, destructive }
    let title: String
    var systemImage: String? = nil
    let kind: Kind
    let lit: Bool
    var enabled = true
    var width: CGFloat = 300
    let action: () -> Void

    private static let label = TextStyle(typeface: .text, size: 29, weight: 600)

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        Button(action: action) {
            HStack(spacing: 14) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 26, weight: .semibold))
                }
                Text(title).textStyle(Self.label)
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 30)
            .frame(minWidth: width)
            .frame(height: 84)
            .background(fill, in: shape)
            .overlay(shape.stroke(lit ? Theme.amethyst : (kind == .secondary ? Theme.line : .clear), lineWidth: lit ? 2 : 1))
            .shadow(color: lit ? Theme.amethyst.opacity(0.35) : .clear, radius: lit ? 24 : 0)
            .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(.tvBare)
        .disabled(!enabled)
        .animation(.easeOut(duration: 0.2), value: lit)
    }

    private var fill: Color {
        switch kind {
        case .primary: return Theme.leafFill
        case .secondary: return lit ? Theme.amethystSoft : Theme.raised
        case .destructive: return Theme.roseSoft
        }
    }

    private var ink: Color {
        switch kind {
        case .primary: return Theme.onLeaf
        case .secondary: return Theme.text
        case .destructive: return Theme.rose
        }
    }
}
#endif
