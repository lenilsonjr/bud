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

    /// A phone-width window: the bar, Files and the palette lay out for one hand. Set from the
    /// size class on iOS, and by a picture that wants the phone layout.
    var compact: Bool {
        get { self[CompactKey.self] }
        set { self[CompactKey.self] = newValue }
    }
}

/// The card a still picture lights, since a picture has no pointer to light one.
struct StillLitKey: EnvironmentKey {
    static let defaultValue: UUID? = nil
}

extension EnvironmentValues {
    var stillLit: UUID? {
        get { self[StillLitKey.self] }
        set { self[StillLitKey.self] = newValue }
    }
}

private struct CompactKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Opens Go anywhere from wherever a gesture asks for it; the root view sets it.
    var goAnywhere: () -> Void {
        get { self[GoAnywhereKey.self] }
        set { self[GoAnywhereKey.self] = newValue }
    }
}

private struct GoAnywhereKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
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

#if canImport(SwiftUI) && !os(tvOS)
/// A drop target for a bud dragged by its id. The picture renderer cannot draw a drop
/// destination, so it is left off in a still picture.
struct BudDrop: ViewModifier {
    @Environment(\.stillPicture) private var still
    let onDrop: (UUID) -> Bool

    func body(content: Content) -> some View {
        if still {
            content
        } else {
            content.dropDestination(for: String.self) { items, _ in
                guard let id = items.first.flatMap(UUID.init(uuidString:)) else { return false }
                return onDrop(id)
            }
        }
    }
}

extension View {
    /// Accepts a dragged bud and hands over its id.
    func budDrop(_ onDrop: @escaping (UUID) -> Bool) -> some View {
        modifier(BudDrop(onDrop: onDrop))
    }
}
#endif
