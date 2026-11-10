#if os(macOS)
import AppKit
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

    /// Closes the panel and makes the app the front one, its window on top.
    private func bringForward() {
        hide()
        NSApp.activate()
        NSApp.windows.first { $0.canBecomeMain && $0.isVisible }?.makeKeyAndOrderFront(nil)
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
/// whenever one is recorded on the sheet, and lets them go at quit. The layout hears when the
/// system refuses one, so the row shows it as taken. The keyboard in use names the keys, and is
/// read again when the input source changes.
@MainActor
final class BudAppDelegate: NSObject, NSApplicationDelegate {
    private var capture: CapturePanelController?
    private var palette: GoAnywherePanelController?
    /// What each row is registered as now, and under which id.
    private var registered: [Command.ID: (key: PhysicalKey, id: UInt32?)] = [:]
    private var feed: AnyCancellable?
    private var inputSource: NSObjectProtocol?

    /// Gives the desktop palette the window's store, once the window is up.
    func attach(_ store: BudStore) {
        guard palette == nil else { return }
        palette = GoAnywherePanelController(store: store)
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
        for entry in registered.values {
            if let id = entry.id { HotKeyCenter.shared.unregister(id) }
        }
        registered = [:]
    }

    /// Registers every system-wide row whose key is not the one registered already, and tells
    /// the layout which the system refused.
    private func register() {
        for id in Command.systemWide {
            guard let key = Keys.layout.hotKey(for: id) else { continue }
            if let entry = registered[id] {
                guard entry.key != key else { continue }
                if let old = entry.id { HotKeyCenter.shared.unregister(old) }
            }
            let handle = HotKeyCenter.shared.register(key) { [weak self] in self?.fire(id) }
            registered[id] = (key, handle)
            Keys.layout.markTakenBySystem(id, handle == nil)
        }
    }

    private func fire(_ id: Command.ID) {
        switch id {
        case .capture: capture?.toggle()
        case .goAnywhereDesktop: palette?.toggle()
        default: break
        }
    }
}
#endif
