import AppKit
import SwiftUI

final class PopupManager: NSObject, NSPopoverDelegate {
    let popover: NSPopover
    var onClose: (() -> Void)?
    var isShown: Bool { popover.isShown }
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?

    override init() {
        popover = NSPopover()
        popover.contentSize = ModulePopupView.popupSize(for: .cpu)
        popover.behavior = .transient
        popover.animates = true
        super.init()
        popover.delegate = self
    }

    func show<V: View>(content: V, size: NSSize, relativeTo rect: NSRect, of view: NSView) {
        stopEventMonitors()
        popover.contentSize = size
        let hostingController = NSHostingController(rootView: content)
        hostingController.view.frame = NSRect(origin: .zero, size: size)
        popover.contentViewController = hostingController
        popover.show(relativeTo: rect, of: view, preferredEdge: .minY)
        startEventMonitors()
    }

    func close() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            stopEventMonitors()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        stopEventMonitors()
        onClose?()
    }

    private func startEventMonitors() {
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self = self else { return event }
            let popoverWindow = self.popover.contentViewController?.view.window
            if event.window !== popoverWindow {
                self.close()
            }
            return event
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            self?.close()
        }
    }

    private func stopEventMonitors() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
    }
}
