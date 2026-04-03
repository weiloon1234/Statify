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
    private var networkInfoLoaded = false
    private var refreshTask: Task<Void, Never>?

    init() {
        self.stats = monitor.stats
    }

    func refresh(
        processMode: ProcessMonitor.SampleMode? = nil,
        force: Bool = false,
        forceNetworkInfo: Bool = false
    ) {
        if force, let refreshTask {
            refreshTask.cancel()
            self.refreshTask = nil
        }

        if let processMode {
            processes = processMonitor.sample(mode: processMode) { [weak self] updatedProcesses in
                self?.applyProcessSample(updatedProcesses)
            }
        }

        if forceNetworkInfo {
            networkInfoLoaded = true
            loadNetworkInfo()
        } else if !networkInfoLoaded {
            networkInfoLoaded = true
            loadNetworkInfo()
        }

        guard refreshTask == nil else {
            return
        }

        let monitor = self.monitor
        refreshTask = Task { [weak self] in
            let stats = await Task.detached(priority: .userInitiated) {
                monitor.sample()
            }.value

            guard !Task.isCancelled, let self = self else { return }
            self.stats = stats
            self.netDownloadHistory.add(stats.downloadKBps)
            self.netUploadHistory.add(stats.uploadKBps)
            self.diskHistory.add(stats.diskUsedGB)
            self.cpuHistory.add(stats.cpuUsage)
            self.memHistory.add(stats.memoryUsage)
            self.refreshTask = nil
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

    private let line1Icon = NSTextField(labelWithString: "")
    private let line1Value = NSTextField(labelWithString: "")
    private let line2Icon = NSTextField(labelWithString: "")
    private let line2Value = NSTextField(labelWithString: "")

    var line1: String {
        get { "" }
        set {
            let parts = newValue.split(separator: "\t", maxSplits: 1)
            line1Icon.stringValue = String(parts[0])
            line1Value.stringValue = parts.count > 1 ? String(parts[1]) : ""
        }
    }

    var line2: String {
        get { "" }
        set {
            let parts = newValue.split(separator: "\t", maxSplits: 1)
            line2Icon.stringValue = String(parts[0])
            line2Value.stringValue = parts.count > 1 ? String(parts[1]) : ""
        }
    }

    init(module: StatModule) {
        self.module = module
        super.init(frame: .zero)

        let font = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
        let isNetwork = module == .network

        let fields = isNetwork
            ? [line1Icon, line1Value, line2Icon, line2Value]
            : [line1Icon, line2Icon]

        fields.forEach {
            $0.font = font
            $0.textColor = .white
            $0.isEditable = false
            $0.isBordered = false
            $0.drawsBackground = false
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        if isNetwork {
            line1Icon.alignment = .left
            line1Value.alignment = .right
            line2Icon.alignment = .left
            line2Value.alignment = .right

            NSLayoutConstraint.activate([
                line1Icon.topAnchor.constraint(equalTo: topAnchor, constant: 1),
                line1Icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
                line1Value.centerYAnchor.constraint(equalTo: line1Icon.centerYAnchor),
                line1Value.leadingAnchor.constraint(equalTo: line1Icon.trailingAnchor, constant: 2),
                line1Value.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
                line2Icon.topAnchor.constraint(equalTo: line1Icon.bottomAnchor, constant: -1),
                line2Icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
                line2Value.centerYAnchor.constraint(equalTo: line2Icon.centerYAnchor),
                line2Value.leadingAnchor.constraint(equalTo: line2Icon.trailingAnchor, constant: 2),
                line2Value.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
                line2Icon.bottomAnchor.constraint(equalTo: bottomAnchor, constant: 0),
            ])
        } else {
            line1Icon.alignment = .center
            line2Icon.alignment = .center

            NSLayoutConstraint.activate([
                line1Icon.topAnchor.constraint(equalTo: topAnchor, constant: 1),
                line1Icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
                line1Icon.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
                line2Icon.topAnchor.constraint(equalTo: line1Icon.bottomAnchor, constant: -1),
                line2Icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
                line2Icon.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
                line2Icon.bottomAnchor.constraint(equalTo: bottomAnchor, constant: 0),
            ])
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(event)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.1).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func makeBackingLayer() -> CALayer { CALayer() }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popupManager = PopupManager()
    var appState: AppState!
    var timerCancellable: AnyCancellable?
    var isPanelOpen = false
    var currentModule: StatModule = .cpu
    var currentButton: ModuleButton?
    var moduleButtons: [StatModule: ModuleButton] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        appState = AppState()
        appState.refresh()
        setupMenuBar()
        startTimer()
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
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 3
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
        currentButton = button
        isPanelOpen = true
        popupManager.onClose = { [weak self] in
            self?.isPanelOpen = false
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
        appState.refresh(processMode: processSampleMode())
        updateMenuBar()
        startTimer()
    }

    @MainActor
    private func refreshCurrentModule() {
        appState.refresh(
            processMode: processSampleMode(),
            force: true,
            forceNetworkInfo: currentModule == .network
        )
        updateMenuBar()
        startTimer()
    }

    func startTimer() {
        timerCancellable?.cancel()
        let interval: TimeInterval = isPanelOpen ? 3.0 : 10.0
        timerCancellable = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.appState.refresh(processMode: self?.processSampleMode())
                    self?.updateMenuBar()
                }
            }
    }

    private func processSampleMode() -> ProcessMonitor.SampleMode? {
        guard isPanelOpen else { return nil }
        switch currentModule {
        case .network:
            return .network
        case .disk:
            return .disk
        case .cpu, .memory:
            return .basic
        case .temperature:
            return nil
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
