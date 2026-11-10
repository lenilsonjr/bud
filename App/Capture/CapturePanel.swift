#if os(macOS)
import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI
import BudKit

/// The Capture panel: the capture face from BudKit floating over whatever app is in front. It
/// remembers which app it was opened over, so the line can say where it came from.
@MainActor
final class CapturePanelController {
    private let panel: DesktopPanel

    init() {
        let size = CapturePanelView.size
        panel = DesktopPanel(size: NSSize(width: size.width + 48, height: size.height + 48))
    }

    func toggle() {
        if panel.isVisible { hide() } else { show() }
    }

    func show() {
        let front = NSWorkspace.shared.frontmostApplication
        let from = front?.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : front?.localizedName
        let face = CapturePanelView(
            from: from,
            onCapture: { line in CaptureRelay.shared.send(line) },
            onClose: { [weak self] in self?.hide() }
        )
        panel.show(face.padding(24))
    }

    func hide() {
        panel.orderOut(nil)
    }
}

/// The Go anywhere panel: the window's palette floating over whatever app is in front, over the
/// window's own store. Return brings the app forward on the row chosen; Esc leaves the front
/// app where it was.
@MainActor
final class GoAnywherePanelController {
    private let panel: DesktopPanel
    private let store: BudStore

    init(store: BudStore) {
        self.store = store
        let size = DesktopPaletteView.size
        panel = DesktopPanel(size: NSSize(width: size.width + 48, height: size.height + 48))
    }

    func toggle() {
        if panel.isVisible { hide() } else { show() }
    }

    func show() {
        let face = DesktopPaletteView(
            store: store,
            onGo: { [weak self] in self?.bringForward() },
            onClose: { [weak self] in self?.hide() }
        )
        panel.show(face.padding(24))
    }

    func hide() {
        panel.orderOut(nil)
    }

    /// Closes the panel and makes the app the front one, its window on top, out of the Dock if
    /// it was put there.
    private func bringForward() {
        hide()
        NSApp.activate()
        guard let window = NSApp.windows.first(where: { $0.canBecomeMain && ($0.isVisible || $0.isMiniaturized) }) else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
    }
}

/// A floating window over whatever app is in front, with one of BudKit's desktop faces inside.
/// It takes the keyboard without activating the app, so the face is typed into over the front
/// app, which stays where it was when the panel goes.
final class DesktopPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(size: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovableByWindowBackground = true
        animationBehavior = .utilityWindow
    }

    /// Puts a face in the panel and brings the panel up, the keyboard with it.
    func show(_ face: some View) {
        contentView = NSHostingView(rootView: face)
        place()
        makeKeyAndOrderFront(nil)
    }

    /// Centred on the screen with the mouse, a third of the way down.
    private func place() {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let screen = screen?.visibleFrame else { center(); return }
        let size = frame.size
        let origin = NSPoint(x: screen.midX - size.width / 2, y: screen.minY + screen.height * 0.62 - size.height / 2)
        setFrameOrigin(origin)
    }
}

/// Registers the keys the Mac answers to from the desktop, from the table at launch and again
/// whenever one is recorded on the sheet, and lets them go at quit. While the sheet records a
/// row they are let go, so the key pressed reaches the recorder and not a panel. The layout
/// hears when the system refuses one, so the row shows it as taken, and such a row is tried
/// again on the next change in case the key was let go. The keyboard in use names the keys, and
/// is read again when the input source changes.
@MainActor
final class BudAppDelegate: NSObject, NSApplicationDelegate {
    private var capture: CapturePanelController?
    private var palette: GoAnywherePanelController?
    private var store: BudStore?
    /// What each row is registered as now, and under which id; nil for one the system refused.
    private var registered: [Command.ID: (key: PhysicalKey, id: UInt32?)] = [:]
    private var feed: AnyCancellable?
    private var inputSource: NSObjectProtocol?

    /// Gives the desktop palette the window's store, once the window is up.
    func attach(_ store: BudStore) {
        guard self.store == nil else { return }
        self.store = store
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        KeyboardLayout.current = .mac
        let changed = Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)
        inputSource = DistributedNotificationCenter.default().addObserver(forName: changed, object: nil, queue: .main) { _ in
            Task { @MainActor in
                KeyboardLayout.current = .mac
                Keys.layout.refresh()
            }
        }
        capture = CapturePanelController()
        register()
        feed = Keys.layout.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.register() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        unregisterAll()
    }

    /// Registers every system-wide row whose key is not the one registered already, or whose
    /// key the system refused last time, and tells the layout which it refuses now. Every row
    /// that changes lets go of its key before any registers, so a key moving from one row to
    /// the other in one change is not refused as a duplicate of itself. While a row records,
    /// every key is let go instead.
    private func register() {
        guard Keys.layout.recording == nil else {
            unregisterAll()
            return
        }
        var due: [(Command.ID, PhysicalKey)] = []
        for id in Command.systemWide {
            guard let key = Keys.layout.hotKey(for: id) else { continue }
            if let entry = registered[id] {
                guard entry.key != key || entry.id == nil else { continue }
                if let old = entry.id { HotKeyCenter.shared.unregister(old) }
                registered[id] = nil
            }
            due.append((id, key))
        }
        for (id, key) in due {
            let handle = HotKeyCenter.shared.register(key) { [weak self] in self?.fire(id) }
            registered[id] = (key, handle)
            Keys.layout.markTakenBySystem(id, handle == nil)
        }
    }

    /// Lets go of every key, the layout's marks left as they were.
    private func unregisterAll() {
        for entry in registered.values {
            if let id = entry.id { HotKeyCenter.shared.unregister(id) }
        }
        registered = [:]
    }

    /// A key pressed from the desktop. Go anywhere needs the window's store; before a window
    /// has been up the app comes forward instead, which brings one.
    private func fire(_ id: Command.ID) {
        switch id {
        case .capture:
            capture?.toggle()
        case .goAnywhereDesktop:
            if palette == nil, let store { palette = GoAnywherePanelController(store: store) }
            if let palette { palette.toggle() } else { NSApp.activate() }
        default:
            break
        }
    }
}
#endif
