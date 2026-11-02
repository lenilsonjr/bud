#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// Whether views are being drawn to a still picture. The picture renderer draws nothing inside a
/// `ScrollView`, so lists lay out flat when this is set.
struct StillPictureKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var stillPicture: Bool {
        get { self[StillPictureKey.self] }
        set { self[StillPictureKey.self] = newValue }
    }
}

/// A vertical scroll view in the app; a plain column in a still picture.
struct MaybeScroll<Content: View>: View {
    @Environment(\.stillPicture) private var still
    @ViewBuilder let content: () -> Content

    var body: some View {
        if still {
            content().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ScrollView { content() }
        }
    }
}
#endif
