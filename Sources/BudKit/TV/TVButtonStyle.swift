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
#endif
