import SwiftUI

struct MiniChart: View {
    let values: [Double]
    let color: Color
    let height: CGFloat

    init(values: [Double], color: Color, height: CGFloat = 40) {
        self.values = values
        self.color = color
        self.height = height
    }

    var body: some View {
        GeometryReader { geo in
            Path { path in
                guard !values.isEmpty else { return }
                let maxVal = values.max() ?? 1
                let stepX = geo.size.width / CGFloat(max(values.count - 1, 1))
                for (i, val) in values.enumerated() {
                    let x = CGFloat(i) * stepX
                    let y = geo.size.height - (CGFloat(val) / CGFloat(maxVal)) * geo.size.height
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(color.opacity(0.7), lineWidth: 1)
        }
        .frame(height: height)
    }
}

struct ModulePopupView: View {
    @ObservedObject var state: AppState
    let module: StatModule
    let onRefresh: () -> Void
    let onClose: () -> Void
    static func popupSize(for module: StatModule) -> NSSize {
        switch module {
        case .cpu:
            return NSSize(width: 344, height: 750)
        case .temperature:
            return NSSize(width: 344, height: 720)
        case .network, .disk, .memory:
            return NSSize(width: 344, height: 560)
        }
    }

    var body: some View {
        let popupSize = Self.popupSize(for: module)
        VStack(spacing: 0) {
            HStack {
                Text(module.popupTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(CP.text)
                Spacer()
                headerButton(icon: "arrow.clockwise.circle", action: onRefresh)
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(CP.textMuted)
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(CP.panel)

            Rectangle().fill(CP.panelBorder).frame(height: 0.5)

            ScrollView {
                switch module {
                case .network: NetworkPopupView(state: state)
                case .disk: DiskPopupView(state: state)
                case .cpu: CpuPopupView(state: state)
                case .temperature: TempPopupView(state: state)
                case .memory: MemPopupView(state: state)
                }
            }
        }
        .frame(width: popupSize.width, height: popupSize.height)
        .background(
            LinearGradient(colors: [CP.bg, CP.bgGradEnd], startPoint: .top, endPoint: .bottom)
        )
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(CP.panelBorder, lineWidth: 0.5)
        )
    }

    private func headerButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(CP.textMuted)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Refresh")
    }
}

struct DiskPopupView: View {
    private static let rootVolumeName: String = {
        let url = URL(fileURLWithPath: "/")
        return (try? url.resourceValues(forKeys: [.volumeNameKey]).volumeName) ?? "Macintosh HD"
    }()

    @ObservedObject var state: AppState
    var stats: SystemStats { state.stats }
    private var freeGB: Double { max(0, stats.diskTotalGB - stats.diskUsedGB) }
    private var usedPercent: Double {
        guard stats.diskTotalGB > 0 else { return 0 }
        return (stats.diskUsedGB / stats.diskTotalGB) * 100.0
    }
    private var diskProcesses: [ProcessStats] {
        state.processes
            .filter { $0.diskReadKBps > 0 || $0.diskWriteKBps > 0 }
            .sorted { ($0.diskReadKBps + $0.diskWriteKBps) > ($1.diskReadKBps + $1.diskWriteKBps) }
    }

    var body: some View {
        let diskProcesses = diskProcesses
        let totalRead = diskProcesses.reduce(0) { $0 + $1.diskReadKBps }
        let totalWrite = diskProcesses.reduce(0) { $0 + $1.diskWriteKBps }
        let peakRead = maxHistory(state.diskReadHistory.values)
        let peakWrite = maxHistory(state.diskWriteHistory.values)

        VStack(alignment: .leading, spacing: 8) {
            diskCapacityCard
            diskIOCard(totalRead: totalRead, totalWrite: totalWrite, peakRead: peakRead, peakWrite: peakWrite)
            diskProcessSection(processes: diskProcesses)
        }
        .padding(8)
    }

    private var diskCapacityCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(CP.textDim.opacity(0.28), lineWidth: 5)

                Circle()
                    .trim(from: 0, to: min(1, usedPercent / 100))
                    .stroke(CP.download, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                Text(String(format: "%.0f", usedPercent))
                    .font(CP.fontMonoLarge)
                    .foregroundColor(CP.text)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 1) {
                Text(Self.rootVolumeName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(CP.text)
                Text("\(formatStorage(freeGB)) available")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.96))
            }
            Spacer()
            VStack(spacing: 12) {
                Circle().fill(CP.upload).frame(width: 8, height: 8)
                Circle().fill(CP.download).frame(width: 8, height: 8)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(CP.panel)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(CP.download, lineWidth: 1)
        )
    }

    private func diskIOCard(totalRead: Double, totalWrite: Double, peakRead: Double, peakWrite: Double) -> some View {
        VStack(spacing: 10) {
            HStack {
                rateSummary(value: formatDiskRate(totalRead), label: "Read", color: CP.upload)
                Spacer()
                rateSummary(value: formatDiskRate(totalWrite), label: "Write", color: CP.download)
            }

            DiskIOBarChart(readValues: state.diskReadHistory.values, writeValues: state.diskWriteHistory.values)
                .padding(.horizontal, 2)
                .padding(.vertical, 4)

            HStack {
                Text("Read \(formatDiskRate(peakRead))")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(.white.opacity(0.95))
                Spacer()
                Text("Write \(formatDiskRate(peakWrite))")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(.white.opacity(0.95))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(CP.panel)
        .cornerRadius(14)
    }

    private func diskProcessSection(processes: [ProcessStats]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("PROCESSES")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(CP.download)
                Spacer()
                Text("R")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.95))
                    .frame(width: 54, alignment: .trailing)
                Text("W")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.95))
                    .frame(width: 54, alignment: .trailing)
            }

            if processes.isEmpty {
                Text("No active disk processes")
                    .font(CP.fontSansSmall)
                    .foregroundColor(CP.textDim)
                    .padding(.vertical, 6)
            } else {
                ForEach(Array(processes.prefix(6).enumerated()), id: \.element.id) { _, process in
                    DiskProcessRow(process: process)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(CP.panel)
        .cornerRadius(14)
    }

    private func rateSummary(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
            HStack(spacing: 5) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                Text(label)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
            }
        }
    }

    private func formatStorage(_ valueGB: Double) -> String {
        String(format: "%.1f GB", valueGB)
    }

    private func formatDiskRate(_ kbps: Double) -> String {
        if kbps >= 1_048_576 {
            return String(format: "%.1f GB/s", kbps / 1_048_576)
        } else if kbps >= 1024 {
            return String(format: "%.1f MB/s", kbps / 1024)
        } else {
            return String(format: "%.0f KB/s", kbps)
        }
    }

    private func maxHistory(_ values: [Double]) -> Double {
        values.max() ?? 0
    }
}

struct DiskIOBarChart: View {
    let readValues: [Double]
    let writeValues: [Double]

    var body: some View {
        GeometryReader { geo in
            let count = max(readValues.count, writeValues.count, 1)
            let groupGap: CGFloat = 1
            let barGap: CGFloat = 1
            let totalGaps = CGFloat(count - 1) * groupGap
            let availableWidth = geo.size.width - totalGaps
            let groupWidth = max(4, availableWidth / CGFloat(count))
            let barWidth = max(1.5, (groupWidth - barGap) / 2)
            let maxVal = max(readValues.max() ?? 1, writeValues.max() ?? 1, 1)
            let midY = geo.size.height / 2
            let maxBarH = midY - 6

            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: midY))
                    path.addLine(to: CGPoint(x: geo.size.width, y: midY))
                }
                .stroke(style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                .foregroundColor(CP.textDim.opacity(0.22))

                ForEach(0..<count, id: \.self) { index in
                    let groupX = CGFloat(index) * (groupWidth + groupGap)
                    let readValue = index < readValues.count ? readValues[index] : 0
                    let writeValue = index < writeValues.count ? writeValues[index] : 0
                    let readHeight = CGFloat(readValue / maxVal) * maxBarH
                    let writeHeight = CGFloat(writeValue / maxVal) * maxBarH

                    if readHeight > 0 {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(CP.upload)
                            .frame(width: barWidth, height: max(1, readHeight))
                            .position(x: groupX + barWidth / 2, y: midY - max(1, readHeight / 2))
                    }

                    if writeHeight > 0 {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(CP.download)
                            .frame(width: barWidth, height: max(1, writeHeight))
                            .position(x: groupX + barWidth + barGap + barWidth / 2, y: midY + max(1, writeHeight / 2))
                    }
                }
            }
        }
        .frame(height: 96)
    }
}

struct DiskProcessRow: View {
    let process: ProcessStats

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: ProcessIconCache.icon(for: process.pid))
                .resizable()
                .frame(width: 16, height: 16)
            Text(truncatedName(process.name))
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(.white.opacity(0.95))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            Text(compactRate(process.diskReadKBps))
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.95))
                .frame(width: 54, alignment: .trailing)
            Text(compactRate(process.diskWriteKBps))
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.95))
                .frame(width: 54, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }

    private func compactRate(_ kbps: Double) -> String {
        if kbps <= 0 {
            return "-"
        }
        if kbps >= 1024 {
            return String(format: "%.1fM", kbps / 1024)
        }
        return String(format: "%.0fK", kbps)
    }

    private func truncatedName(_ name: String) -> String {
        if name.count > 18 {
            return String(name.prefix(16)) + "…"
        }
        return name
    }
}

struct CpuPopupView: View {
    @ObservedObject var state: AppState
    var stats: SystemStats { state.stats }
    var processes: [ProcessStats] { state.processes }
    private var topCPUProcesses: [ProcessStats] {
        let active = processes
            .filter { $0.cpuUsage > 0.1 }
            .sorted { $0.cpuUsage > $1.cpuUsage }
        if !active.isEmpty {
            return Array(active.prefix(5))
        }
        return Array(processes.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            cpuSummaryCard
            CpuCoreRingGrid(
                usages: stats.coreUsages,
                pCoreCount: stats.pCoreCount,
                eCoreCount: stats.eCoreCount
            )
            cpuProcessesSection
            cpuSystemSection
        }
        .padding(8)
    }

    private var cpuSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CPU")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(CP.download)
                    HStack(spacing: 8) {
                        if let cpuGhz = stats.cpuGhz {
                            Text(String(format: "%.2f GHz", cpuGhz))
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                        }
                        if let temp = stats.cpuTemp {
                            Text(String(format: "%.0f°", temp))
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                        }
                    }
                    Text(String(format: "%.0f%% total load", stats.cpuUsage))
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(CP.textMuted)
                        .tracking(0.6)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(stats.chipName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.95))
                    Text("\(stats.totalCores) cores")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(CP.textDim)
                }
            }

            CpuHistoryBars(values: state.cpuHistory.values)
                .frame(height: 34)

            HStack {
                cpuLegend(color: CP.download, label: "User", value: stats.cpuUserUsage)
                Spacer()
                cpuLegend(color: CP.upload, label: "System", value: stats.cpuSystemUsage)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(CP.panel)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(CP.download.opacity(0.9), lineWidth: 1)
        )
    }

    private var cpuProcessesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("PROCESSES")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(CP.download)
                Spacer()
                Text("CPU")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
            }

            ForEach(Array(topCPUProcesses.enumerated()), id: \.element.id) { _, process in
                CpuProcessRow(process: process)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(CP.panel)
        .cornerRadius(14)
    }

    private var cpuSystemSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if stats.gpuGhz != nil || stats.gpuTemp != nil || stats.powerWatts != nil {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("GPU")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(CP.download)
                        Spacer()
                    }
                    HStack(spacing: 10) {
                        cpuSystemMetric(title: "GHZ", value: stats.gpuGhz.map { String(format: "%.2f", $0) } ?? "--")
                        cpuSystemMetric(title: "TMP", value: stats.gpuTemp.map { String(format: "%.0f°", $0) } ?? "--")
                        cpuSystemMetric(title: "PWR", value: stats.powerWatts.map { String(format: "%.1fW", $0) } ?? "--")
                    }
                }
            }

            HStack {
                Text("LOAD")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(CP.download)
                Spacer()
                Text(String(format: "%.2f %.2f %.2f", stats.loadAverage1, stats.loadAverage5, stats.loadAverage15))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.96))
            }
            .padding(.vertical, 2)

            HStack {
                Text("UPTIME")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(CP.download)
                Spacer()
                Text(formatUptime(stats.uptime))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.96))
            }
            .padding(.vertical, 2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(CP.panel)
        .cornerRadius(14)
    }

    private func cpuSystemMetric(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
            Text(title)
                .font(.system(size: 7, weight: .medium))
                .foregroundColor(CP.textMuted)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(CP.surface.opacity(0.6))
        .cornerRadius(12)
    }

    private func cpuLegend(color: Color, label: String, value: Double) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
            Text(String(format: "%.0f%%", value))
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.95))
        }
    }

    private func formatUptime(_ interval: TimeInterval) -> String {
        let totalHours = Int(interval / 3600)
        let days = totalHours / 24
        let hours = totalHours % 24
        if days > 0 {
            return "\(days) day\(days == 1 ? "" : "s"), \(hours) hour\(hours == 1 ? "" : "s")"
        }
        return "\(hours) hour\(hours == 1 ? "" : "s")"
    }
}

struct MemPopupView: View {
    @ObservedObject var state: AppState
    var stats: SystemStats { state.stats }
    var processes: [ProcessStats] { state.processes }
    private var topMem: [ProcessStats] {
        Array(processes.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            memoryRingsCard
            memoryBreakdownCard
            memoryProcessesCard
            memoryPagingCard
        }
        .padding(8)
    }

    private var memoryRingsCard: some View {
        HStack(spacing: 18) {
            VStack(spacing: 4) {
                MemoryRing(
                    value: stats.memoryPressure,
                    segments: [(stats.memoryPressure, CP.download)],
                    valueText: String(format: "%.0f%%", stats.memoryPressure),
                    label: "PRESSURE"
                )
            }

            VStack(spacing: 4) {
                MemoryRing(
                    value: stats.memoryUsage,
                    segments: memorySegments(),
                    valueText: String(format: "%.0f%%", stats.memoryUsage),
                    label: "MEMORY"
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(CP.panel)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(CP.download.opacity(0.9), lineWidth: 1)
        )
    }

    private var memoryBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            memoryBreakdownRow(label: "App", value: stats.memoryAppGB, color: CP.download)
            memoryBreakdownRow(label: "Wired", value: stats.memoryWiredGB, color: CP.upload)
            memoryBreakdownRow(label: "Compressed", value: stats.memoryCompressedGB, color: CP.warning)
            memoryBreakdownRow(label: "Free", value: stats.memoryFreeGB, color: CP.textDim)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(CP.panel)
        .cornerRadius(14)
    }

    private var memoryProcessesCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("PROCESSES")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(CP.download)
                Spacer()
                Text("MEM")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
            }

            ForEach(Array(topMem.enumerated()), id: \.element.id) { _, process in
                MemProcessRow(process: process)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(CP.panel)
        .cornerRadius(14)
    }

    private var memoryPagingCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            memoryMetricRow(label: "Page Ins", value: formatMemoryRate(stats.memoryPageInsKB))
            memoryMetricRow(label: "Page Outs", value: formatMemoryRate(stats.memoryPageOutsKB))
            Rectangle()
                .fill(CP.panelBorder)
                .frame(height: 0.5)
            memoryMetricRow(label: "SWAP", value: formatMemoryIO(stats.memorySwapUsedKB), labelColor: CP.download)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(CP.panel)
        .cornerRadius(14)
    }

    private func memoryBreakdownRow(label: String, value: Double, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
            Spacer()
            Text(String(format: "%.1f GB", value))
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.96))
        }
    }

    private func memoryMetricRow(label: String, value: String, labelColor: Color = .white.opacity(0.9)) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(labelColor)
            Spacer()
            Text(value)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.96))
        }
    }

    private func memorySegments() -> [(Double, Color)] {
        let total = max(stats.memoryTotalGB, 0.0001)
        return [
            (stats.memoryAppGB / total * 100.0, CP.download),
            (stats.memoryWiredGB / total * 100.0, CP.upload),
            (stats.memoryCompressedGB / total * 100.0, CP.warning)
        ]
    }

    private func formatMemoryIO(_ kb: Double) -> String {
        if kb >= 1_048_576 {
            return String(format: "%.1f GB", kb / 1_048_576)
        } else if kb >= 1024 {
            return String(format: "%.1f MB", kb / 1024)
        } else {
            return String(format: "%.0f KB", kb)
        }
    }

    private func formatMemoryRate(_ kbps: Double) -> String {
        if kbps >= 1_048_576 {
            return String(format: "%.1f GB/s", kbps / 1_048_576)
        } else if kbps >= 1024 {
            return String(format: "%.1f MB/s", kbps / 1024)
        } else {
            return String(format: "%.0f KB/s", kbps)
        }
    }
}

struct CpuHistoryBars: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geo in
            let count = max(values.count, 1)
            let gap: CGFloat = 2
            let barWidth = max(3, (geo.size.width - CGFloat(count - 1) * gap) / CGFloat(count))
            let maxValue = max(values.max() ?? 1, 1)

            HStack(alignment: .bottom, spacing: gap) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 1)
                            .fill(
                                LinearGradient(
                                    colors: [CP.download.opacity(0.78), CP.download],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: barWidth, height: max(2, CGFloat(value / maxValue) * geo.size.height))
                    }
                }
            }
        }
    }
}

struct CpuCoreRingGrid: View {
    let usages: [Double]
    let pCoreCount: Int
    let eCoreCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if pCoreCount > 0 {
                coreSection(
                    title: "Performance Cores",
                    values: Array(usages.prefix(pCoreCount)),
                    color: CP.download
                )
            }
            if eCoreCount > 0 {
                coreSection(
                    title: "Efficiency Cores",
                    values: Array(usages.dropFirst(pCoreCount).prefix(eCoreCount)),
                    color: CP.upload
                )
            }
            if pCoreCount == 0 && eCoreCount == 0 {
                coreSection(title: "Cores", values: usages, color: CP.download)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(CP.panel)
        .cornerRadius(14)
    }

    private func coreSection(title: String, values: [Double], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(CP.textMuted)
                Spacer()
                Text(String(format: "%.0f%%", average(values)))
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.92))
            }

            let columns = [
                GridItem(.adaptive(minimum: 42, maximum: 52), spacing: 10)
            ]
            LazyVGrid(columns: columns, alignment: .center, spacing: 10) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    CpuCoreRing(usage: value, color: color)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}

struct CpuCoreRing: View {
    let usage: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(CP.textDim.opacity(0.22), lineWidth: 4)

            Circle()
                .trim(from: 0, to: min(1, usage / 100))
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Text(String(format: "%.0f", usage))
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.95))
        }
        .frame(width: 36, height: 36)
    }
}

struct CpuProcessRow: View {
    let process: ProcessStats

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: ProcessIconCache.icon(for: process.pid))
                .resizable()
                .frame(width: 16, height: 16)
            Text(truncatedName(process.name))
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(.white.opacity(0.95))
                .lineLimit(1)
            Spacer()
            Text(String(format: "%.1f%%", process.cpuUsage))
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.95))
        }
        .padding(.vertical, 2)
    }

    private func truncatedName(_ name: String) -> String {
        if name.count > 22 {
            return String(name.prefix(20)) + "…"
        }
        return name
    }
}

struct TempPopupView: View {
    @ObservedObject var state: AppState
    var stats: SystemStats { state.stats }

    private var sensors: [TemperatureSensor] {
        stats.temperatureSensors.sorted { $0.name < $1.name }
    }

    private var averageFanUsage: Double? {
        guard !stats.fans.isEmpty else { return nil }
        return stats.fans.reduce(0) { $0 + $1.usagePercent } / Double(stats.fans.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            thermalSummaryCard
            temperatureSensorCard
            if !stats.powerReadings.isEmpty {
                powerCard
            }
            if stats.voltage != nil {
                amperageCard
            }
            if !stats.fans.isEmpty {
                fanStatusCard
            }
            frequencyCard
        }
        .padding(8)
    }

    // MARK: - Summary Ring Card

    private var thermalSummaryCard: some View {
        HStack(spacing: 10) {
            ThermalRingMetric(
                title: "CPU",
                valueText: stats.cpuTemp.map { String(format: "%.0f°", $0) } ?? "--",
                subtitle: stats.cpuGhz.map { String(format: "%.2fGHz", $0) } ?? stats.chipName,
                progress: normalizedTempProgress(stats.cpuTemp),
                color: CP.download
            )

            ThermalRingMetric(
                title: "GPU",
                valueText: stats.gpuTemp.map { String(format: "%.0f°", $0) } ?? "--",
                subtitle: stats.gpuGhz.map { String(format: "%.2fGHz", $0) } ?? "--",
                progress: normalizedTempProgress(stats.gpuTemp),
                color: CP.warning
            )

            ThermalRingMetric(
                title: "FANS",
                valueText: averageFanUsage.map { String(format: "%.0f%%", $0) } ?? "--",
                subtitle: stats.fans.isEmpty ? "No fans" : fanSubtitle,
                progress: normalizedPercentProgress(averageFanUsage),
                color: CP.download
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(CP.panel)
        .cornerRadius(14)
    }

    // MARK: - Temperature Section

    private var temperatureSensorCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("TEMPERATURE")

            if sensors.isEmpty {
                Text("No temperature sensors available")
                    .font(CP.fontSansSmall)
                    .foregroundColor(CP.textDim)
                    .padding(.vertical, 4)
            } else {
                ForEach(sensors) { sensor in
                    thermalRow(
                        label: sensor.name,
                        value: String(format: "%.0f°", sensor.valueCelsius),
                        progress: normalizedTempProgress(sensor.valueCelsius)
                    )
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(CP.panel)
        .cornerRadius(14)
    }

    // MARK: - Power Section

    private var powerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("POWER")

            ForEach(stats.powerReadings) { reading in
                metricRow(label: reading.name, value: reading.displayValue)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(CP.panel)
        .cornerRadius(14)
    }

    // MARK: - Amperage / Voltage Section

    private var amperageCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("AMPERAGE")

            if let voltage = stats.voltage {
                metricRow(label: "Power Bus Rail", value: String(format: "%.1f V", voltage))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(CP.panel)
        .cornerRadius(14)
    }

    // MARK: - Fans Section

    private var fanStatusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("FANS")

            ForEach(stats.fans) { fan in
                HStack(spacing: 8) {
                    Text(fan.name)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.white.opacity(0.94))
                    Spacer()
                    Text("\(fan.rpm.formatted()) rpm")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.96))
                    Circle()
                        .stroke(CP.textDim.opacity(0.25), lineWidth: 2)
                        .overlay(
                            Circle()
                                .trim(from: 0, to: normalizedPercentProgress(fan.usagePercent))
                                .stroke(CP.download, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                        )
                        .frame(width: 14, height: 14)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(CP.panel)
        .cornerRadius(14)
    }

    // MARK: - Frequency Section

    private var frequencyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("FREQUENCY")

            if !stats.frequencyReadings.isEmpty {
                ForEach(stats.frequencyReadings) { reading in
                    metricRow(label: reading.name, value: String(format: "%.2f GHz", reading.ghz))
                }
            } else {
                // Fallback to static estimates
                if let cpuGhz = stats.cpuGhz {
                    metricRow(label: "CPU", value: String(format: "%.2f GHz", cpuGhz))
                }
                if let gpuGhz = stats.gpuGhz {
                    metricRow(label: "Graphics", value: String(format: "%.2f GHz", gpuGhz))
                }
                if stats.cpuGhz == nil && stats.gpuGhz == nil {
                    Text("No frequency data available")
                        .font(CP.fontSansSmall)
                        .foregroundColor(CP.textDim)
                        .padding(.vertical, 4)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(CP.panel)
        .cornerRadius(14)
    }

    // MARK: - Helpers

    private var fanSubtitle: String {
        if stats.fans.count == 1 {
            return "1 fan"
        }
        return "\(stats.fans.count) fans"
    }

    private func sectionLabel(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(CP.download)
            Spacer()
        }
    }

    private func thermalRow(label: String, value: String, progress: Double) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(.white.opacity(0.94))
            Spacer()
            Text(value)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.96))
            Circle()
                .stroke(CP.textDim.opacity(0.25), lineWidth: 2)
                .overlay(
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(CP.download, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                )
                .frame(width: 14, height: 14)
        }
    }

    private func metricRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(.white.opacity(0.94))
            Spacer()
            Text(value)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.96))
        }
    }

    private func normalizedTempProgress(_ value: Double?) -> Double {
        normalizedTempProgress(value ?? 0)
    }

    private func normalizedTempProgress(_ value: Double) -> Double {
        max(0.02, min(1, value / 100.0))
    }

    private func normalizedPercentProgress(_ value: Double?) -> Double {
        max(0.02, min(1, (value ?? 0) / 100.0))
    }
}

struct ThermalRingMetric: View {
    let title: String
    let valueText: String
    let subtitle: String
    let progress: Double
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(CP.textDim.opacity(0.22), lineWidth: 4)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 1) {
                    Text(title)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                    Text(valueText)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.system(size: 7, weight: .medium))
                        .foregroundColor(CP.textMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(width: 84, height: 84)
        }
        .frame(width: 92)
    }
}

struct MemoryRing: View {
    let value: Double
    let segments: [(Double, Color)]
    let valueText: String
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(CP.textDim.opacity(0.22), lineWidth: 8)

                segmentedRing

                VStack(spacing: 1) {
                    Text(valueText)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    Text(label)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            .frame(width: 104, height: 104)
        }
    }

    private var segmentedRing: some View {
        ZStack {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                let start = startTrim(for: index)
                let end = start + max(0.001, min(1, segment.0 / 100))
                Circle()
                    .trim(from: start, to: min(end, 1))
                    .stroke(segment.1, style: StrokeStyle(lineWidth: 8, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
        }
    }

    private func startTrim(for index: Int) -> Double {
        let previous = segments.prefix(index).reduce(0.0) { $0 + max(0, min(100, $1.0)) }
        return min(previous / 100.0, 1)
    }
}

struct MemProcessRow: View {
    let process: ProcessStats

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: ProcessIconCache.icon(for: process.pid))
                .resizable()
                .frame(width: 16, height: 16)
            Text(truncatedName(process.name))
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(.white.opacity(0.95))
                .lineLimit(1)
            Spacer()
            Text(formatBytes(process.memoryBytes))
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.96))
        }
        .padding(.vertical, 2)
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824.0
        if gb >= 1.0 { return String(format: "%.1f GB", gb) }
        let mb = Double(bytes) / 1_048_576.0
        return String(format: "%.0f MB", mb)
    }

    private func truncatedName(_ name: String) -> String {
        if name.count > 22 {
            return String(name.prefix(20)) + "…"
        }
        return name
    }
}

func sectionHeader(_ title: String) -> some View {
    HStack(spacing: 6) {
        CornerAccent(color: CP.primary)
        Text(title).font(CP.fontSansBold).foregroundColor(CP.text).tracking(1.5)
        Spacer()
        Rectangle().fill(CP.panelBorder).frame(height: 0.5)
    }
}

func sectionSubHeader(_ title: String) -> some View {
    Text(title).font(CP.fontSansSmall).foregroundColor(CP.textMuted).tracking(1)
        .padding(.top, 4)
}

func infoBlock(label: String, value: String, color: Color) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        Text(label).font(CP.fontSansSmall).foregroundColor(CP.textMuted)
        Text(value).font(CP.fontMono).foregroundColor(color)
    }
}
