import XCTest
@testable import BudKit

#if os(iOS)
import SwiftUI
import UIKit

/// The screen catalog as the iOS app draws it: the same screens, names and sizes as the Mac's
/// catalog, which both read from `Catalog.screens`, laid out with the iPhone and iPad rules
/// (size classes, safe areas, the sidebars that follow the window) the Mac renderer cannot show.
///
/// The test runs inside the app on a simulator. Each shot is a view of the shot's size, added to
/// the app's own window and hosting the root view, with the horizontal size class set to the
/// window's width; it is given a moment to lay out and settle, then read back with
/// `drawHierarchy`. Rendering offscreen leaves Files empty, and a second window is resized to
/// the scene whatever size it is given, so neither will do. The scroll views draw here, so no
/// picture lays its lists out flat as the Mac's do.
///
/// Nothing is compared: every picture lands in `catalog` inside `BUD_SNAPSHOT_DIR`, beside
/// `manifest.txt`, which is the Mac's folder layout, and is attached to the test result as well.
/// A shot that cannot be taken fails naming the screen and the rest still run. Like the Mac's,
/// the catalog only runs when `BUD_SNAPSHOT_DIR` is set; `scripts/ios-catalog.sh` sets it.
@MainActor
final class IOSCatalogTests: XCTestCase {
    /// How long a shot is left to lay out and settle before it is read back.
    private static let settle: TimeInterval = 0.6

    func testEveryScreen() throws {
        let out = try pictureFolder("catalog")
        let catalog = Catalog.screens
        for screen in catalog {
            for shot in screen.shots { try Catalog.note(screen.name(shot), .planned, in: out) }
        }
        for screen in catalog {
            for shot in screen.shots {
                let name = screen.name(shot)
                do {
                    let store = stillStore()
                    store.sidebar = SidebarVisibility(followsWindow: shot.window.followsWindow)
                    try screen.prepare(store)
                    let image = try picture(
                        of: BudRootView(store: store), size: shot.window.size,
                        compact: shot.window.compact, scheme: shot.scheme)
                    try keep(image, named: name, in: out)
                } catch {
                    try Catalog.note(name, .failed, in: out)
                    XCTFail("\(name) could not be taken: \(error)")
                }
            }
        }
    }

    /// The phone palette on its own, as `Catalog.phonePalette` says.
    func testThePhonePalette() throws {
        let out = try pictureFolder("catalog")
        let names = Catalog.phonePalette
        for (_, name) in names { try Catalog.note("modal.\(name)", .planned, in: out) }
        let store = stillStore()
        store.sidebar = SidebarVisibility(followsWindow: true)
        for (scheme, name) in names {
            let sheet = CommandPalette(store: store, inSheet: true) { store.searching = false }
                .frame(width: Catalog.phonePaletteSize.width, height: Catalog.phonePaletteSize.height)
                .background(Theme.raised)
                .environment(\.compact, true)
            let image = try picture(of: sheet, size: Catalog.phonePaletteSize, compact: true, scheme: scheme)
            try keep(image, named: "modal.\(name)", in: out)
        }
    }

    // MARK: Keeping

    /// The picture into `out` under its name, a line in the manifest, and an attachment that
    /// stays with the test result.
    private func keep(_ image: UIImage, named name: String, in out: URL) throws {
        let data = try XCTUnwrap(image.pngData(), "\(name) has no PNG data")
        try data.write(to: out.appendingPathComponent("\(name).png"))
        try Catalog.note(name, .taken, in: out)
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "\(name).png"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: Rendering

    /// One shot of `content`: a view of exactly `size` points in the app's window, hosting the
    /// content with the size class and appearance the shot asks for, read back at one pixel per
    /// point once it has settled. The view leaves the window again whatever happens.
    private func picture(of content: some View, size: CGSize, compact: Bool, scheme: ColorScheme) throws -> UIImage {
        let window = try XCTUnwrap(Self.appWindow, "The app has no window to draw in")
        let parent = try XCTUnwrap(window.rootViewController, "The app's window has no root view controller")
        let host = UIHostingController(rootView: AnyView(
            content
                .environment(\.colorScheme, scheme)
                .transaction { $0.animation = nil }))
        host.traitOverrides.horizontalSizeClass = compact ? .compact : .regular
        host.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        // A child of the window's own controller, so the traits reach it the usual way, with its
        // view on the window itself at a fixed frame the window never resizes.
        parent.addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = true
        host.view.autoresizingMask = []
        host.view.frame = CGRect(origin: .zero, size: size)
        window.addSubview(host.view)
        host.didMove(toParent: parent)
        defer {
            host.willMove(toParent: nil)
            host.view.removeFromSuperview()
            host.removeFromParent()
        }

        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: Self.settle))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        var drawn = false
        let image = renderer.image { _ in
            drawn = host.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
        return try XCTUnwrap(drawn ? image : nil, "drawHierarchy drew nothing")
    }

    /// The window of the app hosting the tests: the key window of its first scene.
    private static var appWindow: UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.lazy.compactMap { $0.keyWindow ?? $0.windows.first }.first
    }
}
#endif
