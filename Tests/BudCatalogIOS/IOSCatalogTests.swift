import XCTest
@testable import BudKit

#if os(iOS)
import SwiftUI
import UIKit

/// The screen catalog as the iOS app draws it: the same screens, names and sizes as the Mac's
/// catalog, which both read from `Catalog.screens`, laid out with the iPhone and iPad rules
/// (size classes, safe areas, the sidebars that follow the window) the Mac renderer cannot show.
///
/// The test runs inside the app on a simulator, the app launched for pictures so it syncs,
/// fires and listens for nothing. Each shot is a view of the shot's size, added to the app's own
/// view as a child controller, hosting the root view over a still store with flags of its own,
/// and the horizontal size class set to the window's width; it is given a moment to lay out and
/// settle, then read back with `drawHierarchy`. Rendering offscreen leaves Files empty, and a
/// second window is resized to the scene whatever size it is given, so neither will do. The
/// scroll views draw here, so no picture lays its lists out flat as the Mac's do.
///
/// A shot is only as big as the screen can show: the shots that fit the screen as it stands are
/// taken first, then the screen turns the other way and the ones that fit now are taken, and
/// the rest are skipped with the reason in the manifest, which is every Mac window and, on a
/// screen that will not turn, the landscape iPad.
///
/// Nothing is compared: every picture lands in `catalog` inside `BUD_SNAPSHOT_DIR`, beside
/// `manifest.txt`, which is the Mac's folder layout, and is attached to the test result as well.
/// A shot that cannot be taken fails naming the screen and the rest still run. Like the Mac's,
/// the catalog only runs when `BUD_SNAPSHOT_DIR` is set; `scripts/ios-catalog.sh` sets it.
@MainActor
final class IOSCatalogTests: XCTestCase {
    /// How long a shot is left to lay out and settle before it is read back.
    private static let settle: TimeInterval = 0.6
    /// How long the screen is given to turn.
    private static let turning: TimeInterval = 1.5

    func testEveryScreen() throws {
        let out = try pictureFolder("catalog")
        let shots = Catalog.screens.flatMap { screen in screen.shots.map { (screen: screen, shot: $0) } }
        for (screen, shot) in shots { try Catalog.note(screen.name(shot), .planned, in: out) }
        var left = shots
        var room = try self.room()
        for turned in [false, true] where !left.isEmpty {
            if turned { room = try turn(from: room) }
            let now = left.filter { Self.fits($0.shot.window.size, in: room) }
            left = left.filter { !Self.fits($0.shot.window.size, in: room) }
            for (screen, shot) in now {
                let name = screen.name(shot)
                do {
                    let store = stillStore()
                    store.sidebar = SidebarVisibility(followsWindow: shot.window.followsWindow)
                    try screen.prepare(store)
                    let root = BudRootView(store: store, flags: stillFlags(shot.scheme), listensForCaptures: false)
                    let image = try picture(of: root, size: shot.window.size, compact: shot.window.compact, scheme: shot.scheme)
                    try keep(image, named: name, in: out)
                } catch {
                    try Catalog.note(name, .failed, in: out)
                    XCTFail("\(name) could not be taken: \(error)")
                }
            }
        }
        for (screen, shot) in left {
            try Catalog.note(screen.name(shot), .skipped, because: Self.misfit(shot.window.size, in: room), in: out)
        }
    }

    /// The phone palette on its own, as `Catalog.phonePalette` says.
    func testThePhonePalette() throws {
        let out = try pictureFolder("catalog")
        let names = Catalog.phonePalette
        for (_, name) in names { try Catalog.note("modal.\(name)", .planned, in: out) }
        let room = try self.room()
        let store = stillStore()
        store.sidebar = SidebarVisibility(followsWindow: true)
        for (scheme, name) in names {
            guard Self.fits(Catalog.phonePaletteSize, in: room) else {
                try Catalog.note("modal.\(name)", .skipped, because: Self.misfit(Catalog.phonePaletteSize, in: room), in: out)
                continue
            }
            let image = try picture(of: Catalog.phonePaletteSheet(store), size: Catalog.phonePaletteSize, compact: true, scheme: scheme)
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

    // MARK: The screen

    private static func fits(_ size: CGSize, in room: CGSize) -> Bool {
        size.width <= room.width && size.height <= room.height
    }

    /// Why a shot does not fit, as the manifest says it.
    private static func misfit(_ size: CGSize, in room: CGSize) -> String {
        switch (size.width > room.width, size.height > room.height) {
        case (true, true): return "larger than screen"
        case (true, false): return "wider than screen"
        default: return "taller than screen"
        }
    }

    /// The room a shot has: the size of the app's own view, which fills the window.
    private func room() throws -> CGSize {
        try Self.parent().view.bounds.size
    }

    /// Turns the screen the other way from `room` and waits for the app's view to follow. A
    /// screen that will not turn keeps its room, and what did not fit stays skipped.
    private func turn(from room: CGSize) throws -> CGSize {
        let scene = try XCTUnwrap(Self.parent().view.window?.windowScene, "The app's window has no scene")
        let other: UIInterfaceOrientationMask = room.width < room.height ? .landscapeRight : .portrait
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: other)) { error in
            NSLog("The screen did not turn: \(error)")
        }
        let deadline = Date(timeIntervalSinceNow: Self.turning)
        while Date() < deadline, try self.room() == room {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: Self.settle))
        return try self.room()
    }

    // MARK: Rendering

    /// One shot of `content`: a view of exactly `size` points on the app's own view, its
    /// controller a child of the app's, hosting the content with the size class and appearance
    /// the shot asks for, read back at one pixel per point once it has settled. The view and
    /// its controller leave again whatever happens.
    private func picture(of content: some View, size: CGSize, compact: Bool, scheme: ColorScheme) throws -> UIImage {
        let parent = try Self.parent()
        let host = UIHostingController(rootView: AnyView(
            content
                .environment(\.colorScheme, scheme)
                .transaction { $0.animation = nil }))
        host.traitOverrides.horizontalSizeClass = compact ? .compact : .regular
        host.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        parent.addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = true
        host.view.autoresizingMask = []
        host.view.frame = CGRect(origin: .zero, size: size)
        parent.view.addSubview(host.view)
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

    /// The controller of the app hosting the tests: the root of its first scene's key window.
    private static func parent() throws -> UIViewController {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = try XCTUnwrap(scenes.lazy.compactMap { $0.keyWindow ?? $0.windows.first }.first, "The app has no window to draw in")
        return try XCTUnwrap(window.rootViewController, "The app's window has no root view controller")
    }
}
#endif
