#if os(macOS)
import AppKit
import SwiftUI
import BudKit

/// The ⌥Space panel: a floating, non-activating window over whatever app is in front, with the
/// capture face from BudKit inside. It remembers which app it was opened over, so the line can
/// say where it came from.
@MainActor
final class CapturePanelController {
    private let panel: CapturePanel

    init() {
        let size = CapturePanelView.size
        panel = CapturePanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: size.width + 48, height: size.height + 48)),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .utilityWindow
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
        panel.contentView = NSHostingView(rootView: face.padding(24))
        place()
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel.orderOut(nil)
    }

    /// Centred on the screen with the mouse, a third of the way down.
    private func place() {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { panel.center(); return }
        let size = panel.frame.size
        let origin = NSPoint(x: frame.midX - size.width / 2, y: frame.minY + frame.height * 0.62 - size.height / 2)
        panel.setFrameOrigin(origin)
    }
}

/// A panel that takes the keyboard without activating the app, so the line is typed over
/// whatever was in front.
final class CapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Registers the Capture key from the table at launch and lets it go at quit.
final class BudAppDelegate: NSObject, NSApplicationDelegate {
    private var panel: CapturePanelController?
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let panel = CapturePanelController()
        self.panel = panel
        guard let carbon = HotKey.carbon(Keys.key(for: .capture)) else { return }
        let key = HotKey(keyCode: carbon.code, modifiers: carbon.modifiers) { [weak panel] in
            panel?.toggle()
        }
        key.register()
        hotKey = key
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKey?.unregister()
        hotKey = nil
    }
}
#endif
