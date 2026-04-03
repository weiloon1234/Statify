import AppKit

class PopupWindow: NSPanel {
    private var closeHandler: (() -> Void)?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var localKeyMonitor: Any?

    init(contentView: NSView, closeHandler: @escaping () -> Void) {
        self.closeHandler = closeHandler
        super.init(contentRect: NSRect(x: 0, y: 0, width: 380, height: 460),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.level = .popUpMenu
        self.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        self.contentView = contentView
        self.hidesOnDeactivate = false
        self.becomesKeyOnlyIfNeeded = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.closeHandler?()
                return nil
            }
            return event
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self else { return event }
            if let eventWindow = event.window, eventWindow != self {
                self.closeHandler?()
                return nil
            }
            return event
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closeHandler?()
        }

        orderFront(nil)
    }

    override func close() {
        if let m = localKeyMonitor { NSEvent.removeMonitor(m); localKeyMonitor = nil }
        if let m = localMouseMonitor { NSEvent.removeMonitor(m); localMouseMonitor = nil }
        if let m = globalMouseMonitor { NSEvent.removeMonitor(m); globalMouseMonitor = nil }
        super.close()
    }
}
