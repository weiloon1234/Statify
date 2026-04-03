import AppKit
import SwiftUI

class PopupPanel: NSPanel {
    private var onClose: (() -> Void)?
    private var blocker: OverlayWindow?
    private var localKeyMonitor: Any?

    init<V: View>(rootView: V, onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 460),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.level = .popUpMenu
        self.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        self.hidesOnDeactivate = false
        self.contentView = NSHostingController(rootView: rootView).view
    }

    func show(relativeTo rect: NSRect, of view: NSView, preferredEdge: NSRectEdge) {
        startMonitors()
        showBlocker()

        let screenRect = view.window?.convertToScreen(rect) ?? .zero
        var frame = self.frame
        frame.size = NSSize(width: 380, height: 460)
        frame.origin.x = screenRect.midX - frame.width / 2
        frame.origin.y = screenRect.minY - frame.height

        if let screen = NSScreen.screens.first(where: { $0.frame.contains(screenRect.origin) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            frame.origin.x = max(visible.minX, min(frame.origin.x, visible.maxX - frame.width))
        }

        setFrame(frame, display: true)
        orderFront(nil)
    }

    private func showBlocker() {
        blocker = OverlayWindow { [weak self] in
            self?.close()
        }
        blocker?.orderFront(nil)
    }

    private func startMonitors() {
        stopMonitors()

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.close()
                return nil
            }
            return event
        }
    }

    private func stopMonitors() {
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
    }

    override func close() {
        stopMonitors()
        blocker?.close()
        blocker = nil
        super.close()
        onClose?()
    }
}

class OverlayWindow: NSWindow {
    private var onClick: (() -> Void)?

    init(onClick: @escaping () -> Void) {
        self.onClick = onClick
        if let screen = NSScreen.main {
            super.init(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
        } else {
            super.init(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
        }
        self.isOpaque = false
        self.backgroundColor = NSColor.black.withAlphaComponent(0.001)
        self.level = .screenSaver - 1
        self.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = false
        self.hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}
