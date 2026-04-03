import SwiftUI
import Combine
import AppKit
import ServiceManagement

enum StatModule: String, CaseIterable {
    case network = "NET"
    case disk = "SSD"
    case cpu = "CPU"
    case temperature = "TMP"
    case memory = "MEM"

    var popupTitle: String {
        switch self {
        case .network:
            return "Network Activity"
        case .disk:
            return "Storage Activity"
        case .cpu:
            return "CPU Monitor"
        case .temperature:
            return "Temperature Monitor"
        case .memory:
            return "Memory Monitor"
        }
    }
}

@MainActor
class AppState: ObservableObject {
    @Published var stats: SystemStats
    @Published var processes: [ProcessStats] = []
    @Published var networkInfo: NetworkInfo = NetworkInfo()

    let netDownloadHistory = HistoryTracker(maxPoints: 30, key: "net_dl")
    let netUploadHistory = HistoryTracker(maxPoints: 30, key: "net_ul")
    let diskHistory = HistoryTracker(maxPoints: 30, key: "disk")
    let diskReadHistory = HistoryTracker(maxPoints: 30, key: "disk_read")
    let diskWriteHistory = HistoryTracker(maxPoints: 30, key: "disk_write")
    let cpuHistory = HistoryTracker(maxPoints: 30, key: "cpu")
    let memHistory = HistoryTracker(maxPoints: 30, key: "mem")

    private let monitor = SystemMonitor()
    private let processMonitor = ProcessMonitor()
    private let networkInfoService = NetworkInfoService()
    private let sampleQueue = DispatchQueue(label: "com.statify.sample", qos: .utility)
    private var networkInfoLoaded = false
    private var isSampling = false
    private var currentScope: SystemMonitor.Scope = .statusBar

    init() {
        self.stats = monitor.stats
    }

    func refresh(scope: SystemMonitor.Scope? = nil, force: Bool = false, forceNetworkInfo: Bool = false) {
        if force {
            isSampling = false
        }

        let targetScope = scope ?? currentScope
        currentScope = targetScope

        let needsProcesses = targetScope != .statusBar && targetScope != .temperaturePopup
        if needsProcesses {
            let processMode: ProcessMonitor.SampleMode
            switch targetScope {
            case .networkPopup: processMode = .network
            case .diskPopup: processMode = .disk
            case .cpuPopup, .memoryPopup: processMode = .basic
            case .temperaturePopup: processMode = .basic
            case .statusBar: processMode = .basic
            }
            processes = processMonitor.sample(mode: processMode) { [weak self] updatedProcesses in
                self?.applyProcessSample(updatedProcesses)
            }
        } else {
            processes = []
        }

        if forceNetworkInfo {
            networkInfoLoaded = true
            loadNetworkInfo()
        } else if !networkInfoLoaded {
            networkInfoLoaded = true
            loadNetworkInfo()
        }

        guard !isSampling else { return }
        isSampling = true

        let monitor = self.monitor
        sampleQueue.async { [weak self] in
            let start = CFAbsoluteTimeGetCurrent()
            let stats = monitor.sample(scope: targetScope)
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            #if DEBUG
            print("[Statify] sample took \(String(format: "%.1f", elapsed * 1000))ms scope=\(targetScope)")
            #endif

            guard let self = self else { return }
            DispatchQueue.main.async {
                self.stats = stats
                self.netDownloadHistory.add(stats.downloadKBps)
                self.netUploadHistory.add(stats.uploadKBps)
                self.diskHistory.add(stats.diskUsedGB)
                self.cpuHistory.add(stats.cpuUsage)
                self.memHistory.add(stats.memoryUsage)
                self.isSampling = false
            }
        }
    }

    private func applyProcessSample(_ processes: [ProcessStats]) {
        self.processes = processes
        let totalDiskRead = processes.reduce(0) { $0 + $1.diskReadKBps }
        let totalDiskWrite = processes.reduce(0) { $0 + $1.diskWriteKBps }
        diskReadHistory.add(totalDiskRead)
        diskWriteHistory.add(totalDiskWrite)
    }

    func loadNetworkInfo() {
        let local = networkInfoService.getLocalInfo()
        networkInfo = local
        networkInfoService.getPublicInfo { [weak self] publicInfo in
            Task { @MainActor in
                self?.networkInfo.publicIP = publicInfo.publicIP
                self?.networkInfo.countryCode = publicInfo.countryCode
                self?.networkInfo.countryName = publicInfo.countryName
                self?.networkInfo.countryFlag = publicInfo.countryFlag
            }
        }
    }
}

class ModuleButton: NSView {
    let module: StatModule
    var onClick: (() -> Void)?
    var onRightClick: ((NSEvent) -> Void)?

    private var topText = ""
    private var bottomText = ""
    private var isHovered = false

    private let font = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
    private lazy var textAttributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white
    ]

    var line1: String {
        get { topText }
        set {
            guard newValue != topText else { return }
            topText = newValue
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    var line2: String {
        get { bottomText }
        set {
            guard newValue != bottomText else { return }
            bottomText = newValue
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    init(module: StatModule) {
        self.module = module
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        let top = (topText as NSString).size(withAttributes: textAttributes)
        let bottom = (bottomText as NSString).size(withAttributes: textAttributes)
        let width = max(top.width, bottom.width) + 4
        let height = top.height + bottom.height + 1
        return NSSize(width: width, height: height)
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHovered {
            NSColor.white.withAlphaComponent(0.1).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 3, yRadius: 3).fill()
        }

        let lineHeight = bounds.height / 2

        if module == .network {
            let topParts = topText.split(separator: "\t", maxSplits: 1)
            let bottomParts = bottomText.split(separator: "\t", maxSplits: 1)

            let topIcon = topParts.first.map(String.init) ?? ""
            let topValue = topParts.count > 1 ? String(topParts[1]) : ""
            let bottomIcon = bottomParts.first.map(String.init) ?? ""
            let bottomValue = bottomParts.count > 1 ? String(bottomParts[1]) : ""

            (topIcon as NSString).draw(at: NSPoint(x: 2, y: lineHeight + 1), withAttributes: textAttributes)
            (bottomIcon as NSString).draw(at: NSPoint(x: 2, y: 0), withAttributes: textAttributes)

            let topValSize = (topValue as NSString).size(withAttributes: textAttributes)
            let bottomValSize = (bottomValue as NSString).size(withAttributes: textAttributes)
            (topValue as NSString).draw(at: NSPoint(x: bounds.width - topValSize.width - 2, y: lineHeight + 1), withAttributes: textAttributes)
            (bottomValue as NSString).draw(at: NSPoint(x: bounds.width - bottomValSize.width - 2, y: 0), withAttributes: textAttributes)
        } else {
            let topSize = (topText as NSString).size(withAttributes: textAttributes)
            let bottomSize = (bottomText as NSString).size(withAttributes: textAttributes)
            (topText as NSString).draw(at: NSPoint(x: (bounds.width - topSize.width) / 2, y: lineHeight + 1), withAttributes: textAttributes)
            (bottomText as NSString).draw(at: NSPoint(x: (bounds.width - bottomSize.width) / 2, y: 0), withAttributes: textAttributes)
        }
    }

    override func mouseDown(with event: NSEvent) { onClick?() }
    override func rightMouseDown(with event: NSEvent) { onRightClick?(event) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingAreas.first, existing.rect == bounds { return }
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popupManager = PopupManager()
    var appState: AppState!
    var timerCancellable: AnyCancellable?
    var isPanelOpen = false
    var currentModule: StatModule = .cpu
    var currentScope: SystemMonitor.Scope = .statusBar
    var currentButton: ModuleButton?
    var moduleButtons: [StatModule: ModuleButton] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        appState = AppState()
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            guard let self = self else { return }
            self.setupMenuBar()
            self.appState.refresh()
            self.startTimer()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @MainActor
    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = ""
        statusItem.button?.image = nil

        let containerView = NSView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        statusItem.button?.addSubview(containerView)

        let modules: [StatModule] = [.network, .disk, .cpu, .temperature, .memory]
        var prevView: NSView?

        for module in modules {
            let btn = ModuleButton(module: module)
            btn.onClick = { [weak self] in
                self?.handleModuleClick(module, button: btn)
            }
            btn.onRightClick = { [weak self] event in
                self?.showContextMenu(for: btn, event: event)
            }
            moduleButtons[module] = btn
            containerView.addSubview(btn)
            btn.translatesAutoresizingMaskIntoConstraints = false

            NSLayoutConstraint.activate([
                btn.topAnchor.constraint(equalTo: containerView.topAnchor),
                btn.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
                btn.widthAnchor.constraint(equalToConstant: 42),
            ])

            if let prev = prevView {
                btn.leadingAnchor.constraint(equalTo: prev.trailingAnchor, constant: 0).isActive = true
            } else {
                btn.leadingAnchor.constraint(equalTo: containerView.leadingAnchor).isActive = true
            }
            prevView = btn
        }

        if let last = prevView {
            last.trailingAnchor.constraint(equalTo: containerView.trailingAnchor).isActive = true
        }

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: statusItem.button!.topAnchor, constant: 0),
            containerView.bottomAnchor.constraint(equalTo: statusItem.button!.bottomAnchor, constant: 0),
            containerView.leadingAnchor.constraint(equalTo: statusItem.button!.leadingAnchor, constant: 2),
            containerView.trailingAnchor.constraint(equalTo: statusItem.button!.trailingAnchor, constant: -2),
        ])

        updateMenuBar()
    }

    @MainActor
    func handleModuleClick(_ module: StatModule, button: ModuleButton) {
        if popupManager.isShown && currentModule == module {
            popupManager.close()
            isPanelOpen = false
            startTimer()
            return
        }

        currentModule = module
        currentScope = moduleToScope(module)
        currentButton = button
        isPanelOpen = true
        popupManager.onClose = { [weak self] in
            self?.isPanelOpen = false
            self?.currentScope = .statusBar
            self?.startTimer()
        }

        let view = ModulePopupView(
            state: appState,
            module: currentModule,
            onRefresh: { [weak self] in
                self?.refreshCurrentModule()
            },
            onClose: { [weak self] in
                self?.popupManager.close()
            }
        )

        popupManager.show(
            content: view,
            size: ModulePopupView.popupSize(for: currentModule),
            relativeTo: button.bounds,
            of: button
        )

        if !popupManager.isShown {
            isPanelOpen = false
            currentScope = .statusBar
            startTimer()
            return
        }

        appState.refresh(scope: moduleToScope(currentModule))
        updateMenuBar()
        startTimer()
    }

    @MainActor
    private func refreshCurrentModule() {
        appState.refresh(
            scope: moduleToScope(currentModule),
            force: true,
            forceNetworkInfo: currentModule == .network
        )
        updateMenuBar()
        startTimer()
    }

    func startTimer() {
        timerCancellable?.cancel()
        let interval: TimeInterval = isPanelOpen ? 5.0 : 10.0
        timerCancellable = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.appState.refresh(scope: self?.currentScope)
                    self?.updateMenuBar()
                }
            }
    }

    private func moduleToScope(_ module: StatModule) -> SystemMonitor.Scope {
        switch module {
        case .cpu: return .cpuPopup
        case .memory: return .memoryPopup
        case .temperature: return .temperaturePopup
        case .network: return .networkPopup
        case .disk: return .diskPopup
        }
    }

    @MainActor
    func updateMenuBar() {
        let s = appState.stats
        let colW = 6

        let diskUsagePercent = s.diskTotalGB > 0 ? (s.diskUsedGB / s.diskTotalGB) * 100.0 : 0
        let ssdVal = String(format: "%.0f%%", diskUsagePercent.rounded())
        let cpuVal = String(format: "%.0f%%", s.cpuUsage)
        let tempVal = s.cpuTemp.map { String(format: "%.0f°", $0.rounded()) } ?? "--°"
        let memVal = String(format: "%.0f%%", s.memoryPressure)

        let upVal = formatSpeedValue(s.uploadKBps, colW: colW)
        let downVal = formatSpeedValue(s.downloadKBps, colW: colW)

        moduleButtons[.network]?.line1 = "↑\t\(upVal)"
        moduleButtons[.network]?.line2 = "↓\t\(downVal)"

        moduleButtons[.disk]?.line1 = "SSD".rightPad(to: colW)
        moduleButtons[.disk]?.line2 = ssdVal.rightPad(to: colW)

        moduleButtons[.cpu]?.line1 = "CPU".rightPad(to: colW)
        moduleButtons[.cpu]?.line2 = cpuVal.rightPad(to: colW)

        moduleButtons[.temperature]?.line1 = "CPU".rightPad(to: colW)
        moduleButtons[.temperature]?.line2 = tempVal.rightPad(to: colW)

        moduleButtons[.memory]?.line1 = "MEM".rightPad(to: colW)
        moduleButtons[.memory]?.line2 = memVal.rightPad(to: colW)
    }

    func formatSpeedValue(_ kbps: Double, colW: Int) -> String {
        let val: String
        if kbps >= 1_048_576 {
            val = String(format: "%.1fG", kbps / 1_048_576)
        } else if kbps >= 1024 {
            val = String(format: "%.1fM", kbps / 1024)
        } else {
            val = String(format: "%.0fK", kbps)
        }
        return val.rightPad(to: colW - 1)
    }

    // MARK: - Context Menu

    @MainActor
    private func showContextMenu(for button: ModuleButton, event: NSEvent) {
        if popupManager.isShown {
            popupManager.close()
            isPanelOpen = false
        }

        let menu = NSMenu()

        let launchItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchItem.target = self
        launchItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(launchItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Statify",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        if service.status == .enabled {
            try? service.unregister()
        } else {
            try? service.register()
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
