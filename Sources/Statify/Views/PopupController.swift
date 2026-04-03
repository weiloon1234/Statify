import AppKit
import SwiftUI

class PopupController<Content: View> {
    var popover: NSPopover!
    var statusItem: NSStatusItem!
    var contentBuilder: () -> Content
    var onClose: (() -> Void)?
    var isShown = false

    init(contentBuilder: @escaping () -> Content) {
        self.contentBuilder = contentBuilder
    }

    func setup(statusItem: NSStatusItem) {
        self.statusItem = statusItem
        popover = NSPopover()
        popover.contentSize = NSSize(width: 380, height: 460)
        popover.behavior = .transient
    }

    func show(relativeTo button: NSView) {
        popover.contentViewController = NSHostingController(rootView: contentBuilder())
        isShown = true
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
    }

    func close() {
        if isShown {
            popover.performClose(nil)
            isShown = false
        }
        onClose?()
    }
}
